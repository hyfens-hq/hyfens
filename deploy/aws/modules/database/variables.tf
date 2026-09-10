variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)

  validation {
    condition     = length(var.private_subnet_ids) == 3
    error_message = "The RDS Multi-AZ cluster requires three private subnets."
  }
}

variable "application_security_group_id" {
  type        = string
  description = "ECS task security group allowed to connect to PostgreSQL."
}

variable "availability_zones" {
  type = list(string)

  validation {
    condition     = length(var.availability_zones) == 3
    error_message = "The RDS Multi-AZ cluster requires exactly three AZs."
  }
}

variable "engine_version" {
  type        = string
  description = "Optional region-supported PostgreSQL engine version."
  default     = null
  nullable    = true
}

variable "instance_class" {
  type        = string
  description = "RDS Multi-AZ DB cluster instance class."
  default     = "db.m6gd.large"
}

variable "allocated_storage_gib" {
  type    = number
  default = 100
}

variable "iops" {
  type    = number
  default = 1000
}

variable "database_name" {
  type    = string
  default = "hyfens"
}

variable "master_username" {
  type      = string
  sensitive = true
  default   = "hyfens_admin"
}

variable "backup_retention_days" {
  type    = number
  default = 7
}
