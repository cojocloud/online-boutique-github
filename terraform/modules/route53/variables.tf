variable "parent_zone_name" {
  type        = string
  description = "Name of the existing Route53 hosted zone (e.g. cojocloudsolutions.com)"
}

variable "subdomain" {
  type        = string
  description = "Fully-qualified subdomain to create (e.g. online-boutique.cojocloudsolutions.com)"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace where the frontend-external service is deployed"
  default     = "online-boutique"
}
