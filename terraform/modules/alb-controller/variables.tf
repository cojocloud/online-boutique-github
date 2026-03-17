variable "cluster_name" {
  type        = string
  description = "EKS cluster name"
}

variable "aws_region" {
  type        = string
  description = "AWS region"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the EKS cluster runs"
}

variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the EKS OIDC provider (for IRSA)"
}
