output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider (for IRSA)"
  value       = module.eks.oidc_provider_arn
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "kubeconfig_command" {
  description = "Run this to configure kubectl for the dev cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "github_ci_role_arn" {
  description = "Set this as GH_AWS_ROLE_ARN in GitHub Actions Variables to enable OIDC auth"
  value       = module.github_oidc.role_arn
}

output "elasticache_endpoint" {
  description = "ElastiCache Redis primary endpoint (null when disabled)"
  value       = var.enable_elasticache ? module.elasticache[0].primary_endpoint : null
}

output "frontend_url" {
  description = "Frontend URL — available after dns:apply stage"
  value       = var.enable_route53 ? module.route53[0].frontend_url : null
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN — available after dns:apply stage"
  value       = var.enable_acm ? module.acm[0].certificate_arn : null
}
