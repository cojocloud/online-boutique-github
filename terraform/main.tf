# ── Root module – delegates to reusable child modules ─────────────────────────
#
# This is the default entry point for a single-environment workflow.
# For explicit per-environment configurations (recommended for teams), use:
#   terraform/environments/dev/
#   terraform/environments/prod/
#
# Usage:
#   cd terraform/
#   terraform init -backend-config="bucket=..." -backend-config="dynamodb_table=..."
#   terraform apply
# ──────────────────────────────────────────────────────────────────────────────

module "vpc" {
  source = "./modules/vpc"

  cluster_name       = var.cluster_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
}

module "eks" {
  source = "./modules/eks"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets
  namespace          = var.namespace

  # Expose API publicly in dev/staging; lock down in prod
  cluster_endpoint_public_access = var.environment != "prod"

  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_disk_size      = var.node_disk_size
}

module "elasticache" {
  count  = var.enable_elasticache ? 1 : 0
  source = "./modules/elasticache"

  cluster_name           = var.cluster_name
  environment            = var.environment
  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_subnets
  node_security_group_id = module.eks.node_security_group_id
  node_type              = var.elasticache_node_type
}

# Bootstrap GitLab OIDC trust. After the first apply, copy the role_arn output
# and set it as CI_AWS_ROLE_ARN in GitLab → Settings → CI/CD → Variables.
module "gitlab_oidc" {
  source = "./modules/gitlab-oidc"

  gitlab_project_path = var.gitlab_project_path
  allowed_branches    = var.environment == "prod" ? "main" : "*"
  tf_state_bucket     = var.tf_state_bucket
  tf_lock_table       = var.tf_lock_table
}

# Write the ElastiCache endpoint into a Kubernetes ConfigMap for cartservice
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
