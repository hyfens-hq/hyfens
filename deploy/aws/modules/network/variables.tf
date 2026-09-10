variable "name" {
  type        = string
  description = "Environment name used in resource names and tags."
}

variable "vpc_cidr" {
  type        = string
  description = "Private CIDR for the disposable VPC."
  default     = "10.77.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  description = "Exactly three AZs; RDS Multi-AZ DB clusters require three."

  validation {
    condition     = length(var.availability_zones) == 3
    error_message = "The disposable profile requires exactly three AZs."
  }
}

variable "region" {
  type        = string
  description = "AWS region used for endpoint service names."
}

variable "allowed_ingress_cidrs" {
  type        = list(string)
  description = "Explicit operator CIDRs allowed to reach the disposable ALB."

  validation {
    condition = length(var.allowed_ingress_cidrs) > 0 && alltrue([
      for cidr in var.allowed_ingress_cidrs : cidr != "0.0.0.0/0"
    ])
    error_message = "Set one or more explicit operator CIDRs; 0.0.0.0/0 is not allowed."
  }
}

variable "https_enabled" {
  type        = bool
  description = "Whether the ALB should admit HTTPS in addition to HTTP."
  default     = false
}

variable "application_port" {
  type    = number
  default = 18081
}
