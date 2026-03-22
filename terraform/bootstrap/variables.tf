variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "github_repository" {
  type        = string
  description = "GitHub repository in the form 'org/repo' (e.g. my-org/online-boutique)"
}

variable "tf_state_bucket" {
  type        = string
  description = "S3 bucket for Terraform remote state"
}

variable "tf_lock_table" {
  type        = string
  description = "DynamoDB table for Terraform state locking"
}
