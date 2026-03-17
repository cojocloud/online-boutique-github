output "iam_role_arn" {
  description = "ARN of the IAM role used by the AWS Load Balancer Controller"
  value       = module.lbc_irsa_role.iam_role_arn
}
