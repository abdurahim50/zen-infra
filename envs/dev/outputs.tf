# Values published by the dev stack after apply.
# Read them with: terraform output <name>

output "vpc_id" {
  description = "Dev VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Dev private subnet IDs (EKS nodes and pods)"
  value       = module.vpc.private_subnet_ids
}

output "database_subnet_ids" {
  description = "Dev database subnet IDs (RDS only)"
  value       = module.vpc.database_subnet_ids
}
