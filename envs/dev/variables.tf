variable "aws_region" {
  description = "aws region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "project name use in names tags"
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
