output "fixed_kibana_url" {
  description = "static kibana url"
  value       = "http://${aws_eip.monitoring_static_ip.public_ip}:5601"
}

output "fixed_server_public_ip" {
  description = "static public IP for ssh and fleet"
  value       = aws_eip.monitoring_static_ip.public_ip
}

output "rds_endpoint" {
  description = "The connection endpoint for the RDS instance"
  value       = aws_db_instance.mysql_db.endpoint
}

output "elastic_aws_access_key_id" {
  description = "Copy this into Kibana (Access Key ID)"
  value       = aws_iam_access_key.elastic_monitor_keys.id
}

output "elastic_aws_secret_access_key" {
  description = "Copy this into Kibana (Secret Access Key)"
  value       = aws_iam_access_key.elastic_monitor_keys.secret
  sensitive   = true
}