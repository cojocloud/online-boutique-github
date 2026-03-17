# ── EKS Cluster ───────────────────────────────────────────────────────────────

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Keep the API endpoint private in prod; allow public access in lower envs
  cluster_endpoint_public_access  = var.cluster_endpoint_public_access
  cluster_endpoint_private_access = true

  # IRSA enables pods to assume scoped IAM roles — no node-level credentials
  enable_irsa = true

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent    = true
      before_compute = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
    }
  }

  eks_managed_node_groups = {
    general = {
      name           = "workers"
      instance_types = var.node_instance_types

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      disk_size = var.node_disk_size

      # Amazon Linux 2023 — latest LTS EKS-optimised AMI
      ami_type = "AL2023_x86_64_STANDARD"

      labels = {
        role = "general"
      }

      # Enforce IMDSv2 to prevent SSRF-based credential theft
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }
    }
  }

  # Grant the Terraform/CI caller cluster-admin so it can manage Kubernetes objects
  enable_cluster_creator_admin_permissions = true
}

# ── IAM – EBS CSI driver IRSA ─────────────────────────────────────────────────

module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${var.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    eks = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# ── Application namespace with Pod Security Standards enforcement ──────────────

resource "kubernetes_namespace" "app" {
  metadata {
    name = var.namespace

    labels = {
      app = "online-boutique"

      # "baseline" blocks known privilege-escalation vectors (hostPID, hostNetwork,
      # privileged containers) without requiring every pod to explicitly configure
      # seccompProfile and drop all capabilities — appropriate for demo workloads.
      # Upgrade to "restricted" once all deployments carry full security contexts.
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }

  depends_on = [module.eks]
}
