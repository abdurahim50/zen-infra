# Inputs for the RDS PostgreSQL module (ZPP-36).

variable "name" {
  description = "Name prefix for the database and its resources, e.g. zen-pharma-dev."
  type        = string

  validation {
    condition     = startswith(var.name, "zen-pharma-")
    error_message = "name must start with zen-pharma-."
  }
}

variable "engine_version" {
  description = "Exact PostgreSQL version, e.g. 18.6. Pinned so upgrades happen by pull request."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.engine_version))
    error_message = "engine_version must look like 18.6."
  }
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage_gb" {
  description = "Encrypted gp3 storage in GiB."
  type        = number
  default     = 20
}

variable "database_name" {
  description = "Name of the initial database."
  type        = string
  default     = "pharmadb"
}

variable "master_username" {
  description = "Master user name. The password is generated and stored by RDS in Secrets Manager; Terraform never sees it."
  type        = string
  default     = "pharma_admin"
}

variable "vpc_id" {
  description = "VPC that holds the database subnets."
  type        = string
}

variable "database_subnet_ids" {
  description = "Database-tier subnet IDs from the VPC module (no route to the internet)."
  type        = list(string)

  validation {
    condition     = length(var.database_subnet_ids) >= 2
    error_message = "RDS needs subnets in at least 2 availability zones."
  }
}

variable "allowed_security_group_id" {
  description = "The only security group allowed to reach PostgreSQL on 5432 (the EKS cluster security group)."
  type        = string
}

variable "multi_az" {
  description = "Standby in a second AZ. Off in dev (doubles the cost); on in prod."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Days of automated backups (point-in-time restore). At least 1, so backups are always tested."
  type        = number
  default     = 1

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 1 and 35."
  }
}

variable "deletion_protection" {
  description = "Block deletion of the instance. Off in dev because the stack is destroyed after each session; on in prod."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on delete. True only in dev, where snapshots would pile up after each session."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Days to keep the PostgreSQL log in CloudWatch."
  type        = number
  default     = 7
}
