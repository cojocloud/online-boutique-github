# ── ACM Certificate with Route53 DNS Validation ───────────────────────────────
#
# Requests an ACM certificate for the frontend subdomain and validates it
# automatically via DNS (CNAME records created in the existing Route53 zone).
#
# Applied in the dns:apply pipeline stage, after app:deploy, so the ELB already
# exists when the Route53 CNAME record is also created.
# ─────────────────────────────────────────────────────────────────────────────

data "aws_route53_zone" "parent" {
  name         = var.parent_zone_name
  private_zone = false
}

resource "aws_acm_certificate" "frontend" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# DNS validation records — one CNAME per domain (only one domain here)
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.frontend.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.parent.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

# Wait for certificate validation (can take 5–15 minutes)
resource "aws_acm_certificate_validation" "frontend" {
  certificate_arn         = aws_acm_certificate.frontend.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}
