# Values envs/dev and later tickets need: kubectl access, the RDS security
# group rule (ZPP-36) and Pod Identity associations (ZPP-37).

output "cluster_name" {
  description = "EKS cluster name (aws eks update-kubeconfig --name ...)"
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 CA certificate for the API endpoint"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group EKS creates for the control plane and managed nodes; RDS allows 5432 from it (ZPP-36)"
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "secrets_kms_key_arn" {
  description = "KMS key that encrypts Kubernetes secrets"
  value       = aws_kms_key.eks.arn
}
