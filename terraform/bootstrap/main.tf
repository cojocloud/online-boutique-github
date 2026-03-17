# ── Bootstrap — one-time local run to create the GitLab OIDC provider + IAM role ──
#
# Run this ONCE before the pipeline can authenticate:
#
#   cd terraform/bootstrap
#   terraform init \
#     -backend-config="bucket=my-tf-state-online-boutique" \
#     -backend-config="region=us-east-1" \
#     -backend-config="dynamodb_table=tf-state-lock"
#   terraform apply \
#     -var="gitlab_project_path=newthiesco/online-boutique" \
#     -var="tf_state_bucket=my-tf-state-online-boutique" \
#     -var="tf_lock_table=tf-state-lock"
#   terraform output gitlab_ci_role_arn   # → set as CI_AWS_ROLE_ARN in GitLab
#
# After this, the full pipeline handles everything else.
# ─────────────────────────────────────────────────────────────────────────────

module "gitlab_oidc" {
  source = "../modules/gitlab-oidc"

  gitlab_project_path = var.gitlab_project_path
  allowed_branches    = "*"
  tf_state_bucket     = var.tf_state_bucket
  tf_lock_table       = var.tf_lock_table
}
