variable "name" {
  type = string
}

variable "database_cluster_arn" {
  type = string
}

variable "retention_days" {
  type    = number
  default = 7
}

variable "tags" {
  type    = map(string)
  default = {}
}
