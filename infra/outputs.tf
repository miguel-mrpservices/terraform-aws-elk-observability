output "monitoring_server_public_ip" {
  description = "The public IP address of the ELK server"
  value       = aws_instance.monitoring_server.public_ip
}

output "kibana_url" {
  description = "Access link for Kibana"
  value       = "http://${aws_instance.monitoring_server.public_ip}:5601"
}