output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = [for az in var.availability_zones : aws_subnet.public[az].id]
}

output "private_subnet_ids" {
  value = [for az in var.availability_zones : aws_subnet.private[az].id]
}

output "private_subnet_by_az" {
  value = { for az, subnet in aws_subnet.private : az => subnet.id }
}

output "endpoint_security_group_id" {
  value = aws_security_group.vpc_endpoints.id
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "application_security_group_id" {
  value = aws_security_group.application.id
}
