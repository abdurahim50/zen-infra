# Values for envs/dev and for the proof tests.

output "role_arn" {
  description = "IAM role the service account's pods receive"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "IAM role name, for policy simulation"
  value       = aws_iam_role.this.name
}

output "association_id" {
  description = "EKS Pod Identity association ID"
  value       = aws_eks_pod_identity_association.this.association_id
}
