# ── Route53 DNS record for the Online Boutique frontend ───────────────────────
#
# This module runs AFTER the application is deployed (app:deploy pipeline stage).
# It reads the ALB hostname from the frontend Ingress resource (provisioned by
# the AWS Load Balancer Controller) and creates a CNAME record in the existing
# Route53 hosted zone.
#
# Why applied separately from the main terraform apply:
#   The ALB is provisioned by the AWS LBC when the Ingress is created,
#   not by Terraform. The dns:apply job sets enable_route53=true after
#   app:deploy, ensuring the ALB hostname is available before this runs.
# ─────────────────────────────────────────────────────────────────────────────

# Reference the existing hosted zone — do not manage it here
data "aws_route53_zone" "parent" {
  name         = var.parent_zone_name
  private_zone = false
}

# Read the ALB hostname from the Ingress created by kubectl/kustomize
data "kubernetes_ingress_v1" "frontend" {
  metadata {
    name      = "frontend"
    namespace = var.namespace
  }
}

locals {
  alb_hostname = data.kubernetes_ingress_v1.frontend.status[0].load_balancer[0].ingress[0].hostname
}

# CNAME record: online-boutique.cojocloudsolutions.com → <ALB hostname>
resource "aws_route53_record" "frontend" {
  zone_id = data.aws_route53_zone.parent.zone_id
  name    = var.subdomain
  type    = "CNAME"
  ttl     = 60
  records = [local.alb_hostname]
}
