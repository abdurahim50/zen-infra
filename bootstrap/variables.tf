# Inputs for the bootstrap stack. Real values live in git-ignored
# terraform.tfvars; terraform.tfvars.example shows the shape.

variable "github_owner_id" {
  description = "Immutable numeric ID of the GitHub owner, used in the OIDC subject. Kept out of git."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "github_owner_id must be the numeric owner ID."
  }
}

variable "github_repository_id" {
  description = "Immutable numeric ID of the zen-infra repository, used in the OIDC subject. Kept out of git."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "github_repository_id must be the numeric repository ID."
  }
}

variable "github_backend_repository_id" {
  description = "Immutable numeric ID of zen-pharma-backend, used in the OIDC subject. Kept out of git."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_backend_repository_id))
    error_message = "github_backend_repository_id must be the numeric repository ID."
  }
}

variable "github_frontend_repository_id" {
  description = "Immutable numeric ID of zen-pharma-frontend, used in the OIDC subject. Kept out of git."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_frontend_repository_id))
    error_message = "github_frontend_repository_id must be the numeric repository ID."
  }
}
