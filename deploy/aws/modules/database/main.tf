resource "aws_security_group" "database" {
  name        = "${var.name}-database"
  description = "Private PostgreSQL ingress from ECS tasks only"
  vpc_id      = var.vpc_id

  egress {
    description = "Database response traffic"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-database" }
}

resource "aws_vpc_security_group_ingress_rule" "application" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = var.application_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "ECS control-plane tasks"
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = var.private_subnet_ids
  tags       = { Name = "${var.name}-db" }
}

resource "aws_rds_cluster" "this" {
  cluster_identifier              = var.name
  availability_zones              = var.availability_zones
  engine                          = "postgres"
  engine_version                  = var.engine_version
  db_cluster_instance_class       = var.instance_class
  storage_type                    = "io1"
  allocated_storage               = var.allocated_storage_gib
  iops                            = var.iops
  database_name                   = var.database_name
  master_username                 = var.master_username
  manage_master_user_password     = true
  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.database.id]
  backup_retention_period         = var.backup_retention_days
  storage_encrypted               = true
  copy_tags_to_snapshot           = true
  skip_final_snapshot             = true
  deletion_protection             = false
  apply_immediately               = true
  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = { Name = "${var.name}-db-cluster" }
}
