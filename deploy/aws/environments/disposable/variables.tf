variable "aws_region" {
  type        = string
  description = "AWS region for the disposable provider test."
  default     = "ap-south-1"
}

variable "environment_name" {
  type    = string
  default = "hyfens-task78-disposable"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.environment_name))
    error_message = "environment_name must be 3-30 lowercase letters, digits, or hyphens."
  }
}

variable "vpc_cidr" {
  type    = string
  default = "10.77.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  description = "Optional explicit three-AZ list; null selects the first three available AZs."
  default     = null
  nullable    = true

  validation {
    condition     = var.availability_zones == null || length(var.availability_zones) == 3
    error_message = "When supplied, availability_zones must contain exactly three AZs."
  }
}

variable "allowed_ingress_cidrs" {
  type        = list(string)
  description = "Operator CIDRs allowed to reach the public ALB; never use 0.0.0.0/0."
  default     = []

  validation {
    condition = length(var.allowed_ingress_cidrs) > 0 && alltrue([
      for cidr in var.allowed_ingress_cidrs : cidr != "0.0.0.0/0"
    ])
    error_message = "An explicit operator CIDR is required and 0.0.0.0/0 is forbidden."
  }
}

variable "image_uri" {
  type        = string
  description = "Full ECR image URI ending in an exact sha256 digest."
  default     = ""

  validation {
    condition     = var.image_uri == "" || can(regex("@sha256:[0-9a-f]{64}$", var.image_uri))
    error_message = "image_uri must end in @sha256:<64 hex chars>."
  }
}

variable "certificate_arn" {
  type        = string
  description = "Optional prevalidated ACM certificate ARN for HTTPS."
  default     = null
  nullable    = true
}

variable "database_engine_version" {
  type        = string
  description = "Optional PostgreSQL version returned by the regional RDS API."
  default     = null
  nullable    = true
}

variable "database_instance_class" {
  type    = string
  default = "db.m6gd.large"
}

variable "database_allocated_storage_gib" {
  type    = number
  default = 100
}

variable "database_iops" {
  type    = number
  default = 1000
}

variable "database_name" {
  type    = string
  default = "hyfens"
}

variable "database_master_username" {
  type      = string
  sensitive = true
  default   = "hyfens_admin"
}

variable "expected_monthly_cost_usd" {
  type        = number
  description = "Operator-entered current price worksheet result."
  default     = 0
}

variable "max_monthly_cost_usd" {
  type    = number
  default = 250
}

variable "test_run_budget_usd" {
  type    = number
  default = 75
}

variable "max_resource_lifetime_hours" {
  type    = number
  default = 24
}

variable "cost_guardrail_acknowledged" {
  type        = bool
  description = "Explicit operator acknowledgement of the bounded disposable cost plan."
  default     = false
}

variable "allow_destroy" {
  type        = bool
  description = "Must be true for explicit teardown of versioned disposable resources."
  default     = false
}

variable "dns_domain_name" {
  type     = string
  default  = null
  nullable = true
}

variable "dns_zone_id" {
  type     = string
  default  = null
  nullable = true
}

variable "allow_dns_changes" {
  type        = bool
  description = "Explicitly enables optional disposable ACM/Route53 changes."
  default     = false
}
