variable "cluster_name" {
  type        = string
  description = "EKS cluster name (used to prefix ElastiCache resource names)"
}

variable "environment" {
  type        = string
  description = "Deployment environment — controls HA settings"
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the ElastiCache cluster will be deployed"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for the ElastiCache subnet group"
}

variable "node_security_group_id" {
  type        = string
  description = "Security group ID of EKS worker nodes (granted Redis access)"
}

variable "node_type" {
  type        = string
  description = "ElastiCache node type"
  default     = "cache.t3.micro"
}

variable "high_availability" {
  type        = bool
  description = "Enable Multi-AZ failover, 2 replicas, and 7-day snapshots. Disable to reduce cost."
  default     = false
}
