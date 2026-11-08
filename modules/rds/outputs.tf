# Values for envs/dev, External Secrets (Sprint 4) and IAM database
# authentication through Pod Identity.

output "endpoint" {
  description = "Database host name (private DNS, resolves inside the VPC only)"
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Database port"
  value       = aws_db_instance.this.port
}

output "database_name" {
  description = "Initial database name"
  value       = aws_db_instance.this.db_name
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret that RDS created for the master password (the value itself is never in Terraform)"
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "resource_id" {
  description = "DB instance resource ID, used in rds-db:connect IAM policies for IAM database authentication"
  value       = aws_db_instance.this.resource_id
}

output "security_group_id" {
  description = "Security group attached to the database"
  value       = aws_security_group.rds.id
}

output "kms_key_arn" {
  description = "KMS key that encrypts the database storage and the master password secret"
  value       = aws_kms_key.rds.arn
}
