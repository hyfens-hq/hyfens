output "ecr_repository_url" {
  value = aws_ecr_repository.control_plane.repository_url
}

output "ecr_repository_arn" {
  value = aws_ecr_repository.control_plane.arn
}

output "cluster_name" {
  value = aws_ecs_cluster.control_plane.name
}

output "service_name" {
  value = aws_ecs_service.control_plane.name
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.control_plane.arn
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}

output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "alb_dns_name" {
  value = aws_lb.control_plane.dns_name
}

output "alb_arn" {
  value = aws_lb.control_plane.arn
}

output "target_group_arn" {
  value = aws_lb_target_group.control_plane.arn
}

output "task_security_group_id" {
  value = var.application_security_group_id
}

output "alb_security_group_id" {
  value = var.alb_security_group_id
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.control_plane.name
}
