locals {
  az_indexes = {
    for index, az in var.availability_zones : az => index
  }
  private_subnet_cidrs = {
    for az, index in local.az_indexes : az => cidrsubnet(var.vpc_cidr, 4, index + 8)
  }
  public_subnet_cidrs = {
    for az, index in local.az_indexes : az => cidrsubnet(var.vpc_cidr, 4, index)
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${var.name}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-igw" }
}

resource "aws_subnet" "public" {
  for_each                = local.az_indexes
  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = local.public_subnet_cidrs[each.key]
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.name}-public-${each.key}" }
}

resource "aws_subnet" "private" {
  for_each                = local.az_indexes
  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = local.private_subnet_cidrs[each.key]
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.name}-private-${each.key}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${var.name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  for_each = local.az_indexes
  vpc_id   = aws_vpc.this.id
  tags     = { Name = "${var.name}-private-rt-${each.key}" }
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.name}-vpce"
  description = "Private endpoint ingress from disposable VPC"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Endpoint response traffic"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = [var.vpc_cidr]
  }

  tags = { Name = "${var.name}-vpce" }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for route_table in aws_route_table.private : route_table.id]
  tags              = { Name = "${var.name}-s3-endpoint" }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset([
    "ecr.api",
    "ecr.dkr",
    "logs",
    "secretsmanager",
    "sts",
  ])

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [for subnet in aws_subnet.private : subnet.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  tags                = { Name = "${var.name}-${replace(each.key, ".", "-")}-endpoint" }
}

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Explicit disposable operator ingress"
  vpc_id      = aws_vpc.this.id

  dynamic "ingress" {
    for_each = var.allowed_ingress_cidrs
    content {
      description = "Operator HTTP ingress"
      protocol    = "tcp"
      from_port   = 80
      to_port     = 80
      cidr_blocks = [ingress.value]
    }
  }

  dynamic "ingress" {
    for_each = var.https_enabled ? var.allowed_ingress_cidrs : []
    content {
      description = "Operator HTTPS ingress"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-alb" }
}

resource "aws_security_group" "application" {
  name        = "${var.name}-tasks"
  description = "Control-plane tasks accept traffic only from the ALB"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "ALB to control-plane"
    protocol        = "tcp"
    from_port       = var.application_port
    to_port         = var.application_port
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-tasks" }
}
