variable "name" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "ECS requires private subnets in at least two AZs."
  }
}

variable "artifact_bucket_name" {
  type = string
}

variable "artifact_bucket_arn" {
  type = string
}

variable "alb_security_group_id" {
  type = string
}

variable "application_security_group_id" {
  type = string
}

variable "database_writer_endpoint" {
  type = string
}

variable "database_port" {
  type    = number
  default = 5432
}

variable "database_name" {
  type = string
}

variable "database_user" {
  type      = string
  sensitive = true
}

variable "database_secret_arn" {
  type        = string
  description = "RDS-managed Secrets Manager secret containing the password JSON."
}

variable "image_uri" {
  type        = string
  description = "Full registry image reference ending in an immutable sha256 digest."

  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.image_uri))
    error_message = "image_uri must be an exact image digest ending in @sha256:<64 hex chars>."
  }
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "cpu_architecture" {
  type    = string
  default = "ARM64"

  validation {
    condition     = contains(["ARM64", "X86_64"], var.cpu_architecture)
    error_message = "cpu_architecture must be ARM64 or X86_64."
  }
}

variable "desired_count" {
  type    = number
  default = 2

  validation {
    condition     = var.desired_count >= 2
    error_message = "The disposable profile requires two ECS tasks."
  }
}

variable "certificate_arn" {
  type        = string
  description = "Optional disposable ACM certificate ARN. HTTP is used when null."
  default     = null
  nullable    = true
}

variable "app_port" {
  type    = number
  default = 18081
}

variable "log_retention_days" {
  type    = number
  default = 7
}

variable "allow_destroy" {
  type    = bool
  default = false
}

variable "reconciliation_periodic_enabled" {
  type = bool
  # The serving binary currently has no safe exact-tenant invocation/lease
  # wiring. Keep this false until that existing runner seam is connected;
  # infrastructure must not advertise a scheduler it cannot execute safely.
  default = false
}

variable "reconciliation_periodic_interval_seconds" {
  type    = number
  default = 300
}
