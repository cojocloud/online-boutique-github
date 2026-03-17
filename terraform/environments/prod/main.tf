# ── Prod environment – wires together all reusable modules ─────────────────────

module "vpc" {
  source = "../../modules/vpc"

  cluster_name       = var.cluster_name
  environment        = "prod"
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones

  # POC: single NAT gateway to keep costs low.
  # Production recommendation: set to false → one NAT gateway per AZ for HA.
  single_nat_gateway = var.single_nat_gateway
}

module "eks" {
  source = "../../modules/eks"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets
  namespace          = var.namespace

  # POC: public endpoint for easy access without a bastion host or VPN.
  # Production recommendation: set to false — API endpoint accessible only from within the VPC.
  cluster_endpoint_public_access = var.cluster_endpoint_public_access

  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_disk_size      = var.node_disk_size
}

# ElastiCache is always enabled in prod (in-cluster Redis is not suitable for production workloads)
module "elasticache" {
  source = "../../modules/elasticache"

  cluster_name           = var.cluster_name
  environment            = "prod"
  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_subnets
  node_security_group_id = module.eks.node_security_group_id
  node_type              = var.elasticache_node_type

  # POC: HA disabled to reduce cost.
  # Production recommendation: set to true → Multi-AZ failover, 2 replicas, 7-day snapshots.
  high_availability = var.elasticache_high_availability
}

# Prod: only the main branch can assume the GitLab CI role
module "gitlab_oidc" {
  source = "../../modules/gitlab-oidc"

  role_name           = "gitlab-ci-oidc-role-prod"
  gitlab_project_path = var.gitlab_project_path
  allowed_branches    = "main"
  tf_state_bucket     = var.tf_state_bucket
  tf_lock_table       = var.tf_lock_table
}

resource "kubernetes_config_map" "redis_config" {
  metadata {
    name      = "redis-config"
    namespace = var.namespace
  }

  data = {
    redis_addr = "${module.elasticache.primary_endpoint}:${module.elasticache.port}"
  }

  depends_on = [module.eks]
}
