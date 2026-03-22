variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "online-boutique-dev"
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
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  type    = list(string)
  default = []
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "node_disk_size" {
  type    = number
  default = 50
}

variable "enable_elasticache" {
  type    = bool
  default = false
}

variable "elasticache_node_type" {
  type    = string
  default = "cache.t3.micro"
}

# ── Route53 DNS ───────────────────────────────────────────────────────────────

variable "enable_route53" {
  type        = bool
  description = "Create the Route53 CNAME record for the frontend."
  default     = true
}

variable "parent_zone_name" {
  type        = string
  description = "Existing Route53 hosted zone name (e.g. cojocloudsolutions.com)"
  default     = "cojocloudsolutions.com"
}

variable "subdomain" {
  type        = string
  description = "Full subdomain for the app (e.g. online-boutique.cojocloudsolutions.com)"
  default     = "online-boutique.cojocloudsolutions.com"
}

# ── ACM Certificate ──────────────────────────────────────────────────────────

variable "enable_acm" {
  type        = bool
  description = "Request an ACM certificate and validate it via Route53."
  default     = true
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

