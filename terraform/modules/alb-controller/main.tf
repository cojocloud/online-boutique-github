# ── AWS Load Balancer Controller ──────────────────────────────────────────────
#
# Installs the AWS Load Balancer Controller on EKS via Helm.
# The controller provisions ALBs for Kubernetes Ingress resources, enabling:
#   - HTTP → HTTPS redirect (not possible with the classic ELB)
#   - ACM certificate attachment
#   - Fine-grained ALB listener rules
#
# Authentication: IRSA (IAM Role for Service Accounts) — the controller pod
# assumes an IAM role via the EKS OIDC provider, scoped to its ServiceAccount.
# ─────────────────────────────────────────────────────────────────────────────

# IRSA role — grants the controller pod the IAM permissions it needs to
# create/manage ALBs, target groups, security groups, and listeners.
module "lbc_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${var.cluster_name}-aws-load-balancer-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    eks = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# Deploy the controller via the official eks-charts Helm repository
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.8.1"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  # Annotate the ServiceAccount with the IRSA role ARN so the controller
  # pod can assume it without needing node-level credentials
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.lbc_irsa_role.iam_role_arn
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  depends_on = [module.lbc_irsa_role]
}
