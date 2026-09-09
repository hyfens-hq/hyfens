output "region" {
  value = var.aws_region
}

output "availability_zones" {
  value = local.availability_zones
}

output "alb_dns_name" {
  value = module.ecs.alb_dns_name
}

output "alb_arn" {
  value = module.ecs.alb_arn
}

output "ecs_cluster" {
  value = module.ecs.cluster_name
}

output "ecs_service" {
  value = module.ecs.service_name
}

output "task_definition" {
  value = module.ecs.task_definition_arn
}

output "ecr_repository_url" {
  value = module.ecs.ecr_repository_url
}

output "database_writer_endpoint" {
  value = module.database.writer_endpoint
}

output "database_cluster_id" {
  value = module.database.cluster_id
}

output "artifact_bucket_name" {
  value = module.storage.bucket_name
}

output "backup_vault" {
  value = module.backup.vault_name
}

output "dns_enabled" {
  value = module.dns.enabled
}
