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

output "eks_cluster_name" {
  description = "Dev EKS cluster name, for aws eks update-kubeconfig"
  value       = module.eks.cluster_name
}

output "eks_cluster_security_group_id" {
  description = "Security group of the dev cluster and its nodes (RDS ingress source, ZPP-36)"
  value       = module.eks.cluster_security_group_id
}
