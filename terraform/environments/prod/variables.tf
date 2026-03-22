variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "online-boutique-prod"
}

variable "kubernetes_version" {
  type    = string
  default = "1.30"
}

variable "namespace" {
  type    = string
  default = "online-boutique"
}

variable "vpc_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

variable "availability_zones" {
  type    = list(string)
  default = []
}

# ── NAT Gateway ───────────────────────────────────────────────────────────────

variable "single_nat_gateway" {
  type        = bool
  description = "Use one shared NAT gateway (cost-saving). Set to false for one per AZ (HA)."
  # POC default: true  |  Production recommendation: false
  default = true
}

# ── EKS ───────────────────────────────────────────────────────────────────────

variable "cluster_endpoint_public_access" {
  type        = bool
  description = "Expose the Kubernetes API server publicly. Set to false in prod (requires VPN/bastion)."
  # POC default: true  |  Production recommendation: false
  default = true
}

variable "node_instance_types" {
  type        = list(string)
  description = "EC2 instance types for worker nodes."
  # POC default: ["t3.medium"]  |  Production recommendation: ["m5.large"]
  default = ["t3.medium"]
}

variable "node_desired_size" {
  type = number
  # POC default: 2  |  Production recommendation: 3
  default = 2
}

variable "node_min_size" {
  type = number
  # POC default: 1  |  Production recommendation: 3
  default = 1
}

variable "node_max_size" {
  type = number
  # POC default: 4  |  Production recommendation: 10
  default = 4
}

variable "node_disk_size" {
  type = number
  # POC default: 50  |  Production recommendation: 100
  default = 50
}

# ── ElastiCache ───────────────────────────────────────────────────────────────

variable "elasticache_node_type" {
  type        = string
  description = "ElastiCache node type."
  # POC default: "cache.t3.micro"  |  Production recommendation: "cache.r6g.large"
  default = "cache.t3.micro"
}

variable "elasticache_high_availability" {
  type        = bool
  description = "Enable Multi-AZ failover, 2 replicas, and 7-day snapshots."
  # POC default: false  |  Production recommendation: true
  default = false
}

# ── GitHub OIDC ───────────────────────────────────────────────────────────────

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
