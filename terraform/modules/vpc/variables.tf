variable "cluster_name" {
  type        = string
  description = "EKS cluster name (used for VPC name and subnet discovery tags)"
}

variable "environment" {
  type        = string
  description = "Deployment environment label (used for naming)"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "single_nat_gateway" {
  type        = bool
  description = "Use one shared NAT gateway (cost-saving). Set to false for one per AZ (HA)."
  default     = true
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  description = "Explicit list of AZs to use; leave empty to auto-select the first three"
  default     = []
}
