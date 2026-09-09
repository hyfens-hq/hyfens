data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "task_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_ecr_repository" "control_plane" {
  name                 = "${var.name}/control-plane"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = var.allow_destroy

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Name = "${var.name}-control-plane" }
}

resource "aws_ecr_lifecycle_policy" "control_plane" {
  repository = aws_ecr_repository.control_plane.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep a bounded disposable image history"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_iam_role" "execution" {
  name               = "${var.name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
  tags               = { Name = "${var.name}-ecs-execution" }
}

data "aws_iam_policy_document" "execution" {
  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.control_plane.arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.control_plane.arn}:*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.database_secret_arn]
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "${var.name}-ecs-execution"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}

resource "aws_iam_role" "task" {
  name               = "${var.name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
  tags               = { Name = "${var.name}-ecs-task" }
}

data "aws_iam_policy_document" "task" {
  statement {
    sid    = "ListArtifactPrefix"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]
    resources = [var.artifact_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["artifacts/*"]
    }
  }

  statement {
    sid    = "ReadWriteDigestObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["${var.artifact_bucket_arn}/artifacts/*"]
  }
}

resource "aws_iam_role_policy" "task" {
  name   = "${var.name}-ecs-task"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task.json
}

resource "aws_cloudwatch_log_group" "control_plane" {
  name              = "/hyfens/${var.name}/control-plane"
  retention_in_days = var.log_retention_days
  tags              = { Name = "${var.name}-control-plane-logs" }
}

resource "aws_lb" "control_plane" {
  name                       = substr("${var.name}-alb", 0, 32)
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [var.alb_security_group_id]
  subnets                    = var.public_subnet_ids
  drop_invalid_header_fields = true

  tags = { Name = "${var.name}-alb" }
}

resource "aws_lb_target_group" "control_plane" {
  name                 = substr("${var.name}-targets", 0, 32)
  port                 = var.app_port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = "/readyz"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Name = "${var.name}-targets" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.control_plane.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = var.certificate_arn == null ? "forward" : "redirect"

    dynamic "forward" {
      for_each = var.certificate_arn == null ? [1] : []
      content {
        target_group {
          arn = aws_lb_target_group.control_plane.arn
        }
      }
    }

    dynamic "redirect" {
      for_each = var.certificate_arn == null ? [] : [1]
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

resource "aws_lb_listener" "https" {
  count             = var.certificate_arn == null ? 0 : 1
  load_balancer_arn = aws_lb.control_plane.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.control_plane.arn
  }
}

resource "aws_ecs_cluster" "control_plane" {
  name = var.name
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  tags = { Name = "${var.name}-cluster" }
}

resource "aws_ecs_task_definition" "control_plane" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name        = "control-plane"
      image       = var.image_uri
      essential   = true
      stopTimeout = 30
      user        = "65532"
      portMappings = [
        {
          containerPort = var.app_port
          hostPort      = var.app_port
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "HYFENS_HOST", value = "0.0.0.0" },
        { name = "HYFENS_PORT", value = tostring(var.app_port) },
        { name = "HYFENS_DATABASE_HOST", value = var.database_writer_endpoint },
        { name = "HYFENS_DATABASE_PORT", value = tostring(var.database_port) },
        { name = "HYFENS_DATABASE_NAME", value = var.database_name },
        { name = "HYFENS_DATABASE_USER", value = var.database_user },
        { name = "HYFENS_ARTIFACT_ENDPOINT", value = "https://s3.${var.region}.amazonaws.com/" },
        { name = "HYFENS_ARTIFACT_BUCKET", value = var.artifact_bucket_name },
        { name = "HYFENS_ARTIFACT_KEY_PREFIX", value = "artifacts" },
        { name = "HYFENS_ARTIFACT_REGION", value = var.region },
        { name = "HYFENS_ARTIFACT_USE_TASK_ROLE", value = "true" },
        { name = "HYFENS_RECONCILIATION_PERIODIC_ENABLED", value = tostring(var.reconciliation_periodic_enabled) },
        { name = "HYFENS_RECONCILIATION_PERIODIC_INTERVAL_SECONDS", value = tostring(var.reconciliation_periodic_interval_seconds) },
      ]
      secrets = [
        {
          name      = "HYFENS_DATABASE_PASSWORD"
          valueFrom = "${var.database_secret_arn}:password::"
        }
      ]
      healthCheck = {
        # The hardened runtime image contains only the compiled health-check
        # executable; the Dart SDK and source tree are build-stage inputs.
        command     = ["CMD", "/app/health_check"]
        interval    = 15
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.control_plane.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  lifecycle {
    precondition {
      condition     = can(regex("@sha256:[0-9a-f]{64}$", var.image_uri))
      error_message = "The ECS task definition refuses mutable image tags."
    }
  }

  tags = { Name = "${var.name}-task-definition" }
}

resource "aws_ecs_service" "control_plane" {
  name                               = var.name
  cluster                            = aws_ecs_cluster.control_plane.id
  task_definition                    = aws_ecs_task_definition.control_plane.arn
  desired_count                      = var.desired_count
  launch_type                        = "FARGATE"
  platform_version                   = "1.4.0"
  health_check_grace_period_seconds  = 60
  enable_execute_command             = false
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.application_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.control_plane.arn
    container_name   = "control-plane"
    container_port   = var.app_port
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  tags = { Name = "${var.name}-service" }
}
