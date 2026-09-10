variable "domain_name" {
  type        = string
  description = "Optional disposable DNS name. Null leaves TLS/DNS environment-gated."
  default     = null
  nullable    = true
}

variable "zone_id" {
  type        = string
  description = "Existing Route 53 public hosted-zone ID."
  default     = null
  nullable    = true
}

variable "load_balancer_dns_name" {
  type = string
}

variable "load_balancer_zone_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "allow_dns_changes" {
  type        = bool
  description = "Explicitly enables the disposable Route 53 record change."
  default     = false
}
