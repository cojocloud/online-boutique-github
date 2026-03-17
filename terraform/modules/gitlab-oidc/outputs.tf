output "role_arn" {
  description = "ARN of the GitLab CI IAM role — set this as CI_AWS_ROLE_ARN in GitLab CI/CD Variables"
  value       = aws_iam_role.gitlab_ci.arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitLab OIDC provider registered in IAM"
  value       = aws_iam_openid_connect_provider.gitlab.arn
}
