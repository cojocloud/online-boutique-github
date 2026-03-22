# ── Bootstrap — one-time local run to create the GitHub OIDC provider + IAM role ──
#
# Run this ONCE before the pipeline can authenticate:
#
#   cd terraform/bootstrap
#   terraform init \
#     -backend-config="bucket=tf-state-online-boutique-github" \
#     -backend-config="region=us-east-1" \
#     -backend-config="dynamodb_table=tf-state-lock-github"
#   terraform apply \
#     -var="github_repository=your-org/online-boutique" \
#     -var="tf_state_bucket=tf-state-online-boutique-github" \
#     -var="tf_lock_table=tf-state-lock-github"
#   terraform output github_ci_role_arn   # → set as GH_AWS_ROLE_ARN in GitHub Actions Variables
#
# After this, the full pipeline handles everything else.
# ─────────────────────────────────────────────────────────────────────────────

module "github_oidc" {
  source = "../modules/github-oidc"

  github_repository   = var.github_repository
  allowed_ref_pattern = "*"
  tf_state_bucket     = var.tf_state_bucket
  tf_lock_table       = var.tf_lock_table
}
