variable "name" {
  type = string
}

variable "allow_destroy" {
  type        = bool
  description = "Enables versioned-object deletion during explicit disposable teardown."
  default     = false
}

variable "noncurrent_version_days" {
  type        = number
  description = "Retention for noncurrent object versions."
  default     = 30

  validation {
    condition     = var.noncurrent_version_days >= 7
    error_message = "Keep noncurrent versions for at least seven days for recovery evidence."
  }
}
