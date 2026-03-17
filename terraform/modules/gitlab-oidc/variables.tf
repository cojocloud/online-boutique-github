variable "role_name" {
  type        = string
  description = "Name of the IAM role that GitLab CI jobs will assume"
  default     = "gitlab-ci-oidc-role"
}

variable "gitlab_project_path" {
  type        = string
  description = "GitLab project path in the form 'group/project' (e.g. my-org/online-boutique)"
}

variable "allowed_branches" {
  type        = string
  description = "Branch pattern that can assume this role. Use 'main' for prod; '*' for dev/all branches"
  default     = "main"
}

variable "tf_state_bucket" {
  type        = string
  description = "S3 bucket name for Terraform state — scopes the S3 policy to this bucket only"
}

variable "tf_lock_table" {
  type        = string
  description = "DynamoDB table name for Terraform state locking — scopes the DynamoDB policy"
}
