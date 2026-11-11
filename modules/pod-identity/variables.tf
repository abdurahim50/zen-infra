# Inputs for the EKS Pod Identity module: one IAM role per service, bound to
# one Kubernetes namespace and service account, allowed to log in to one
# PostgreSQL user with IAM database authentication. Design: docs/adr/0004-eks-design.md
# (Pod Identity), docs/adr/0005-rds-design.md (IAM database login).

variable "name" {
  description = "Environment name prefix, e.g. zen-pharma-dev. The role is named <name>-<service>-pod."
  type        = string

  validation {
    condition     = startswith(var.name, "zen-pharma-")
    error_message = "name must start with zen-pharma- (the pipeline can only create zen-pharma-* roles)."
  }
}

variable "service" {
  description = "Service name, e.g. inventory. Lowercase letters, digits and hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.service))
    error_message = "service must be lowercase letters, digits and hyphens, 2 to 31 characters, starting with a letter."
  }
}

variable "cluster_name" {
  description = "EKS cluster the association is created in."
  type        = string
}

variable "cluster_arn" {
  description = "ARN of the same cluster; the role's trust policy only accepts sessions from it."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace whose service account may use the role."
  type        = string
}

variable "service_account" {
  description = "Kubernetes service account that may use the role."
  type        = string
}

variable "db_resource_id" {
  description = "RDS instance resource ID (db-...), from the rds module's resource_id output. IAM database login policies use it, not the instance name."
  type        = string

  validation {
    condition     = startswith(var.db_resource_id, "db-")
    error_message = "db_resource_id must be the instance resource ID, starting with db-."
  }
}

variable "db_user" {
  description = "PostgreSQL user this service logs in as. Must start with svc_, the only users the workload boundary allows."
  type        = string

  validation {
    condition     = can(regex("^svc_[a-z0-9_]{1,40}$", var.db_user))
    error_message = "db_user must start with svc_ and use lowercase letters, digits and underscores."
  }
}

variable "permissions_boundary_arn" {
  description = "Workload permissions boundary. Required: the pipeline can only create bounded roles (ADR-002)."
  type        = string
}
