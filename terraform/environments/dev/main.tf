# ── Dev environment – wires together all reusable modules ─────────────────────

module "vpc" {
  source = "../../modules/vpc"

  cluster_name       = var.cluster_name
  environment        = "dev"
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
}

module "eks" {
  source = "../../modules/eks"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets
  namespace          = var.namespace

  # Dev: public API endpoint for easy local kubectl access
  cluster_endpoint_public_access = true

  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_disk_size      = var.node_disk_size
}

module "elasticache" {
  count  = var.enable_elasticache ? 1 : 0
  source = "../../modules/elasticache"

  cluster_name           = var.cluster_name
  environment            = "dev"
  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_subnets
  node_security_group_id = module.eks.node_security_group_id
  node_type              = var.elasticache_node_type
}

# Install the AWS Load Balancer Controller on EKS via Helm.
# Required for ALB-backed Ingress resources with HTTP→HTTPS redirect.
# The controller is installed during terraform:apply so it is ready before
# app:deploy creates the Ingress resource.
# Bootstrap GitHub OIDC trust. After the first apply, copy the role_arn output
# and set it as GH_AWS_ROLE_ARN in GitHub → Settings → Secrets and variables → Actions → Variables.
# Dev: allow all branches so feature-branch pipelines can run plan.
module "github_oidc" {
  source = "../../modules/github-oidc"

  role_name           = "github-ci-oidc-role-dev"
  github_repository   = var.github_repository
  allowed_ref_pattern = "*"
  tf_state_bucket     = var.tf_state_bucket
  tf_lock_table       = var.tf_lock_table
}

module "alb_controller" {
  source = "../../modules/alb-controller"

  cluster_name      = var.cluster_name
  aws_region        = var.aws_region
  vpc_id            = module.vpc.vpc_id
  oidc_provider_arn = module.eks.oidc_provider_arn

  depends_on = [module.eks]
}

# Request an ACM certificate for the subdomain and validate it via Route53 DNS.
# Only applied in the dns:apply pipeline stage via -var="enable_acm=true".
# Certificate validation can take 5–15 minutes (handled by aws_acm_certificate_validation).
module "acm" {
  count  = var.enable_acm ? 1 : 0
  source = "../../modules/acm"

  domain_name      = var.subdomain
  parent_zone_name = var.parent_zone_name
}

# Create the Route53 CNAME record pointing the subdomain to the frontend ELB.
# Only applied AFTER app:deploy (dns:apply pipeline stage) because the ELB
# doesn't exist until Kubernetes creates the frontend-external Service.
# The dns:apply job passes -var="enable_route53=true" to enable this module.
module "route53" {
  count  = var.enable_route53 ? 1 : 0
  source = "../../modules/route53"

  parent_zone_name = var.parent_zone_name
  subdomain        = var.subdomain
  namespace        = var.namespace

  depends_on = [module.eks]
}

# Write the cartservice Redis endpoint into a ConfigMap when ElastiCache is used
resource "kubernetes_config_map" "redis_config" {
  count = var.enable_elasticache ? 1 : 0

  metadata {
    name      = "redis-config"
    namespace = var.namespace
  }

  data = {
    redis_addr = "${module.elasticache[0].primary_endpoint}:${module.elasticache[0].port}"
  }

  depends_on = [module.eks]
}
