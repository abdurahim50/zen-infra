variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name, used in resource names and tags"
  type        = string
  default     = "zen-pharma"
}

variable "environment" {
  description = "Deployment environment"
  type        = string

  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "environment must be dev, qa or prod."
  }
}

variable "owner" {
  description = "Team or person accountable for these resources"
  type        = string
}

variable "cost_center" {
  description = "Cost center for billing reports"
  type        = string
}

variable "eks_public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS public API endpoint, e.g. [\"203.0.113.10/32\"]. Set from the EKS_PUBLIC_ACCESS_CIDRS secret in CI, or terraform.tfvars locally. Never committed."
  type        = list(string)
  sensitive   = true
}
