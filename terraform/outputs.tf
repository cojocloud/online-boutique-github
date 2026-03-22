output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint URL of the EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_region" {
  description = "AWS region of the EKS cluster"
  value       = var.aws_region
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "kubeconfig_command" {
  description = "AWS CLI command to update your local kubeconfig"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "github_ci_role_arn" {
  description = "Set this as GH_AWS_ROLE_ARN in GitHub Actions Variables to enable OIDC auth"
  value       = module.github_oidc.role_arn
}

output "elasticache_endpoint" {
  description = "Primary endpoint of the ElastiCache Redis cluster (null when disabled)"
  value       = var.enable_elasticache ? module.elasticache[0].primary_endpoint : null
}
