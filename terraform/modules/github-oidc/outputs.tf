output "role_arn" {
  description = "ARN of the GitHub CI IAM role — set this as GH_AWS_ROLE_ARN in GitHub Actions Variables"
  value       = aws_iam_role.github_ci.arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider registered in IAM"
  value       = aws_iam_openid_connect_provider.github.arn
}
