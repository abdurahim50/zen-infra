# -----------------------------------------------------------------------------
# Shared container registry (ADR-003)
#
# One set of repositories for every environment: CI builds an image once and
# dev, qa and prod deploy the same digest. Tags are immutable, images are
# scanned on push and encrypted with our own KMS key. Only untagged images
# expire; tagged images may be running somewhere and are never auto-deleted.
# -----------------------------------------------------------------------------

locals {
  services = toset([
    "api-gateway",
    "auth-service",
    "drug-catalog-service",
    "inventory-service",
    "manufacturing-service",
    "notification-service",
    "pharma-ui",
    "qc-service",
    "supplier-service",
  ])
}

resource "aws_kms_key" "ecr" {
  description             = "Encrypts zen-pharma container images in ECR"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "ecr" {
  name          = "alias/${var.project}-ecr"
  target_key_id = aws_kms_key.ecr.key_id
}

resource "aws_ecr_repository" "service" {
  for_each = local.services

  name                 = "${var.project}/${each.key}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }
}

resource "aws_ecr_lifecycle_policy" "service" {
  for_each   = aws_ecr_repository.service
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images 7 days after push"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 7
      }
      action = { type = "expire" }
    }]
  })
}
