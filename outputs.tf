output "alb_dns_name" {
  value       = module.blog_alb.dns_name
  description = "Use this URL in your browser to view the web server live"
}