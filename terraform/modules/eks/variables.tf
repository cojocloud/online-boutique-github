variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version for the EKS cluster"
  default     = "1.30"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the cluster will be deployed"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for EKS worker nodes"
}

variable "cluster_endpoint_public_access" {
  type        = bool
  description = "Expose the Kubernetes API server publicly (disable in prod)"
  default     = true
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace for the application workloads"
  default     = "online-boutique"
}

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
  description = "Root EBS volume size (GiB) per worker node"
  default     = 50
}
