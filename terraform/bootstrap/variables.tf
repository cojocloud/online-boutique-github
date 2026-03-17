variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "gitlab_project_path" {
  type        = string
  description = "GitLab project path (e.g. newthiesco/online-boutique)"
}

variable "tf_state_bucket" {
  type        = string
  description = "S3 bucket for Terraform remote state"
}

variable "tf_lock_table" {
  type        = string
  description = "DynamoDB table for Terraform state locking"
}
