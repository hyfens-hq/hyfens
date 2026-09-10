output "cluster_id" {
  value = aws_rds_cluster.this.id
}

output "cluster_arn" {
  value = aws_rds_cluster.this.arn
}

output "writer_endpoint" {
  value = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  value = aws_rds_cluster.this.reader_endpoint
}

output "port" {
  value = aws_rds_cluster.this.port
}

output "database_name" {
  value = var.database_name
}

output "master_username" {
  value     = var.master_username
  sensitive = true
}

output "master_user_secret_arn" {
  value     = try(aws_rds_cluster.this.master_user_secret[0].secret_arn, null)
  sensitive = true
}

output "security_group_id" {
  value = aws_security_group.database.id
}
