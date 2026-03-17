output "fqdn" {
  description = "The fully-qualified domain name of the frontend"
  value       = aws_route53_record.frontend.fqdn
}

output "alb_hostname" {
  description = "Raw ALB hostname the CNAME points to"
  value       = local.alb_hostname
}

output "frontend_url" {
  description = "Full HTTPS URL to access the application"
  value       = "https://${aws_route53_record.frontend.fqdn}"
}
