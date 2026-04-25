variable "tags" {
  description = "Default tags for all the resources"
  type        = map(string)
  default = {
    Project     = "aws-elk-observability"
    Environment = "test"
    ManagedBy   = "terraform"
  }
}

variable "admin_ip" {
  description = "Public IP for security group whitelisting"
  type        = string
}

variable "db_user" {
  description = "default db user"
  type        = string
}

variable "db_pass" {
  description = "default db pass"
  type        = string
}