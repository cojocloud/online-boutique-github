output "gitlab_ci_role_arn" {
  description = "Set this as CI_AWS_ROLE_ARN in GitLab Settings → CI/CD → Variables"
  value       = module.gitlab_oidc.role_arn
}
