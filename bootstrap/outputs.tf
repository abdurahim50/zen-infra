# Role ARNs the GitHub workflow needs (ZPP-26). They contain the account ID,
# so store them as GitHub variables or secrets, not in the repo.

output "plan_role_arn" {
  description = "Role GitHub Actions assumes for terraform plan on pull requests"
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Role GitHub Actions assumes for terraform apply after approval"
  value       = aws_iam_role.apply.arn
}

output "workload_boundary_arn" {
  description = "Permissions boundary every pipeline-created role must carry"
  value       = aws_iam_policy.workload_boundary.arn
}
