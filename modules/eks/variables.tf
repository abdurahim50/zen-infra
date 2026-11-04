# Inputs for the EKS module. Design and the reasons for each default:
# docs/adr/0004-eks-design.md

variable "name" {
  description = "Cluster name and name prefix for its resources, e.g. zen-pharma-dev. Must start with zen-pharma- so the pipeline may create its IAM roles."
  type        = string

  validation {
    condition     = startswith(var.name, "zen-pharma-")
    error_message = "name must start with zen-pharma- (the apply role can only create zen-pharma-* roles)."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes minor version, e.g. 1.37. Use a version in EKS standard support (ADR-004)."
  type        = string

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.37."
  }
}

variable "private_subnet_ids" {
  description = "Private subnet IDs from the VPC module (at least 2 AZs). The control plane network interfaces and the nodes go here; never the database subnets."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "EKS needs subnets in at least 2 availability zones."
  }
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint (the engineer's /32). Sensitive: kept out of the public plan comment and logs."
  type        = list(string)
  sensitive   = true

  validation {
    condition = alltrue([
      for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0)) && cidr != "0.0.0.0/0"
    ])
    error_message = "public_access_cidrs must be valid CIDRs and must not include 0.0.0.0/0."
  }
}

variable "admin_role_arn" {
  description = "IAM role that gets cluster admin through an access entry (the SSO admin role). The pipeline role never does (ADR-004)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/", var.admin_role_arn))
    error_message = "admin_role_arn must be an IAM role ARN."
  }
}

variable "log_retention_days" {
  description = "Days to keep control-plane logs in CloudWatch."
  type        = number
  default     = 7
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary for IAM roles this module creates. Required: the pipeline can only create bounded roles (ADR-002)."
  type        = string
}
