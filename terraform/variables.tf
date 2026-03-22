variable "aws_region" {
  type        = string
  description = "AWS region where the EKS cluster will be created"
  default     = "us-east-1"
}

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster"
  default     = "online-boutique"
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev, staging, prod)"
  default     = "dev"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version for the EKS cluster"
  default     = "1.30"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace for Online Boutique resources"
  default     = "online-boutique"
}

# ── VPC ──────────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  description = "List of availability zones to use (leave empty to auto-select)"
  default     = []
}

# ── Node Group ────────────────────────────────────────────────────────────────

variable "node_instance_types" {
  type        = list(string)
  description = "EC2 instance types for the managed node group"
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  type        = number
  description = "Desired number of worker nodes"
  default     = 3
}

variable "node_min_size" {
  type        = number
  description = "Minimum number of worker nodes"
  default     = 2
}

variable "node_max_size" {
  type        = number
  description = "Maximum number of worker nodes"
  default     = 6
}

variable "node_disk_size" {
  type        = number
  description = "Root EBS volume size (GiB) for worker nodes"
  default     = 50
}

# ── Application ───────────────────────────────────────────────────────────────

variable "filepath_manifest" {
  type        = string
  description = "Path to the Kubernetes manifest or Kustomize directory"
  default     = "../kubernetes/manifests.yaml"
}

variable "enable_elasticache" {
  type        = bool
  description = "Replace in-cluster Redis with AWS ElastiCache (Redis)"
  default     = false
}

variable "elasticache_node_type" {
  type        = string
  description = "ElastiCache node type when enable_elasticache = true"
  default     = "cache.t3.micro"
}

# ── GitHub OIDC ───────────────────────────────────────────────────────────────

variable "github_repository" {
  type        = string
  description = "GitHub repository in the form 'org/repo' (e.g. my-org/online-boutique) — used to scope the OIDC trust policy"
}

variable "tf_state_bucket" {
  type        = string
  description = "S3 bucket name for Terraform remote state — used to scope the CI IAM policy"
}

variable "tf_lock_table" {
  type        = string
  description = "DynamoDB table name for Terraform state locking — used to scope the CI IAM policy"
}
