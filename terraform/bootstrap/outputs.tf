output "github_ci_role_arn" {
  description = "Set this as GH_AWS_ROLE_ARN in GitHub Actions → Settings → Secrets and variables → Actions → Variables"
  value       = module.github_oidc.role_arn
}
