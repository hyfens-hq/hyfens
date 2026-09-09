locals {
  certificate_enabled = var.domain_name != null && var.zone_id != null && var.allow_dns_changes
  alias_enabled       = local.certificate_enabled && var.load_balancer_dns_name != "" && var.load_balancer_zone_id != ""
}

resource "aws_acm_certificate" "this" {
  count             = local.certificate_enabled ? 1 : 0
  domain_name       = var.domain_name
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
  tags = var.tags
}

resource "aws_route53_record" "validation" {
  for_each = local.certificate_enabled ? {
    for option in aws_acm_certificate.this[0].domain_validation_options : option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  } : {}
  zone_id         = var.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  count                   = local.certificate_enabled ? 1 : 0
  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}

resource "aws_route53_record" "alias" {
  count   = local.alias_enabled ? 1 : 0
  zone_id = var.zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = var.load_balancer_dns_name
    zone_id                = var.load_balancer_zone_id
    evaluate_target_health = true
  }
}
