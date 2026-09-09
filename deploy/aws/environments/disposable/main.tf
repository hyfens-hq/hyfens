data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  availability_zones = var.availability_zones != null ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 3)
  https_enabled      = var.certificate_arn != null
  common_tags = {
    AccountBoundary = data.aws_caller_identity.current.account_id
    CostGuardrail   = "monthly-usd-${var.max_monthly_cost_usd}"
  }
}

resource "terraform_data" "cost_guardrail" {
  input = {
    expected_monthly_cost_usd = var.expected_monthly_cost_usd
    test_run_budget_usd       = var.test_run_budget_usd
    max_resource_lifetime     = var.max_resource_lifetime_hours
  }

  lifecycle {
    precondition {
      condition     = var.cost_guardrail_acknowledged
      error_message = "Set cost_guardrail_acknowledged=true only after reviewing current ap-south-1 prices and the teardown plan."
    }
    precondition {
      condition     = var.expected_monthly_cost_usd > 0 && var.expected_monthly_cost_usd <= var.max_monthly_cost_usd
      error_message = "Enter a positive current price worksheet result within the USD 250 monthly envelope."
    }
    precondition {
      condition     = var.test_run_budget_usd > 0 && var.test_run_budget_usd <= 75
      error_message = "The disposable test-run budget must be positive and no more than USD 75."
    }
    precondition {
      condition     = var.max_resource_lifetime_hours > 0 && var.max_resource_lifetime_hours <= 24
      error_message = "The disposable environment lifetime must not exceed 24 hours."
    }
  }
}

module "network" {
  source = "../../modules/network"

  name                  = var.environment_name
  region                = var.aws_region
  vpc_cidr              = var.vpc_cidr
  availability_zones    = local.availability_zones
  allowed_ingress_cidrs = var.allowed_ingress_cidrs
  https_enabled         = local.https_enabled
  application_port      = 18081
}

module "storage" {
  source = "../../modules/storage"

  name          = var.environment_name
  allow_destroy = var.allow_destroy
}

module "database" {
  source = "../../modules/database"

  name                          = var.environment_name
  vpc_id                        = module.network.vpc_id
  private_subnet_ids            = module.network.private_subnet_ids
  availability_zones            = local.availability_zones
  application_security_group_id = module.network.application_security_group_id
  engine_version                = var.database_engine_version
  instance_class                = var.database_instance_class
  allocated_storage_gib         = var.database_allocated_storage_gib
  iops                          = var.database_iops
  database_name                 = var.database_name
  master_username               = var.database_master_username
}

module "ecs" {
  source = "../../modules/ecs"

  name                          = var.environment_name
  region                        = var.aws_region
  vpc_id                        = module.network.vpc_id
  public_subnet_ids             = module.network.public_subnet_ids
  private_subnet_ids            = module.network.private_subnet_ids
  alb_security_group_id         = module.network.alb_security_group_id
  application_security_group_id = module.network.application_security_group_id
  artifact_bucket_name          = module.storage.bucket_name
  artifact_bucket_arn           = module.storage.bucket_arn
  database_writer_endpoint      = module.database.writer_endpoint
  database_port                 = module.database.port
  database_name                 = module.database.database_name
  database_user                 = module.database.master_username
  database_secret_arn           = module.database.master_user_secret_arn
  image_uri                     = var.image_uri
  certificate_arn               = var.certificate_arn
}

module "backup" {
  source = "../../modules/backup"

  name                 = var.environment_name
  database_cluster_arn = module.database.cluster_arn
  tags                 = local.common_tags
}

# The DNS/ACM module is intentionally inactive unless a disposable public
# domain, hosted-zone ID, and explicit change acknowledgement are provided.
# A certificate ARN can instead be supplied independently after operator
# validation, avoiding an implicit public DNS mutation.
module "dns" {
  source = "../../modules/dns"

  domain_name            = var.dns_domain_name
  zone_id                = var.dns_zone_id
  allow_dns_changes      = var.allow_dns_changes
  load_balancer_dns_name = ""
  load_balancer_zone_id  = ""
  tags                   = local.common_tags
}

data "aws_iam_policy_document" "artifact_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [module.storage.bucket_arn, "${module.storage.bucket_arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "TaskArtifactAccess"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]
    resources = [module.storage.bucket_arn]
    principals {
      type        = "AWS"
      identifiers = [module.ecs.task_role_arn]
    }
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["artifacts/*"]
    }
  }

  statement {
    sid    = "TaskArtifactObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["${module.storage.bucket_arn}/artifacts/*"]
    principals {
      type        = "AWS"
      identifiers = [module.ecs.task_role_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "artifacts" {
  bucket = module.storage.bucket_name
  policy = data.aws_iam_policy_document.artifact_bucket.json
}
