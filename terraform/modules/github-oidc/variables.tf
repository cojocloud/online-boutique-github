variable "role_name" {
  type        = string
  description = "Name of the IAM role that GitHub Actions jobs will assume"
  default     = "github-ci-oidc-role"
}

variable "github_repository" {
  type        = string
  description = "GitHub repository in the form 'org/repo' (e.g. my-org/online-boutique)"
}

variable "allowed_ref_pattern" {
  type        = string
  description = "Ref pattern that can assume this role. Use 'ref:refs/heads/main' for prod; '*' for dev/all refs"
  default     = "ref:refs/heads/main"
}

variable "tf_state_bucket" {
  type        = string
  description = "S3 bucket name for Terraform state — scopes the S3 policy to this bucket only"
}

variable "tf_lock_table" {
  type        = string
  description = "DynamoDB table name for Terraform state locking — scopes the DynamoDB policy"
}
