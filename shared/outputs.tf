# Repository details used by CI (ZPP-28) and by the environments that pull
# images. URLs contain the account ID, so CI reads them from secrets or from
# this state, never from the repo.

output "repository_arns" {
  description = "ECR repository ARN per service (for the CI push policy)"
  value       = { for name, repo in aws_ecr_repository.service : name => repo.arn }
}

output "repository_urls" {
  description = "ECR repository URL per service"
  value       = { for name, repo in aws_ecr_repository.service : name => repo.repository_url }
}

output "ecr_kms_key_arn" {
  description = "KMS key that encrypts the images"
  value       = aws_kms_key.ecr.arn
}
