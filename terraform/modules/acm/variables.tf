variable "domain_name" {
  type        = string
  description = "Fully-qualified domain name for the ACM certificate (e.g. online-boutique.cojocloudsolutions.com)"
}

variable "parent_zone_name" {
  type        = string
  description = "Name of the existing Route53 hosted zone (e.g. cojocloudsolutions.com)"
}
