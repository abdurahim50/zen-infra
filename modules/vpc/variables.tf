# Inputs for the VPC module. Every environment calls this module with its own
# values; the code is identical for dev, qa and prod (see ADR-000 and ADR-001).

variable "name" {
  description = "Name prefix for all resources, e.g. zen-pharma-dev"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC; must not overlap other environments"
  type        = string
}

variable "azs" {
  description = "Availability zones to spread subnets across (at least 2)"
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "Use at least 2 availability zones."
  }
}

variable "public_subnet_cidrs" {
  description = "One public subnet CIDR per AZ, in the same order as azs (load balancers and NAT only)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "One private subnet CIDR per AZ, in the same order as azs (EKS nodes and pods; size for pod IPs)"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "true = one shared NAT gateway (dev, ADR-001); false = one NAT gateway per AZ (prod)"
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Days to keep VPC flow logs in CloudWatch"
  type        = number
  default     = 14
}

variable "database_subnet_cidrs" {
  description = "One database subnet CIDR per AZ, same order as azs (RDS only; no internet route)"
  type        = list(string)
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary for IAM roles this module creates. Required: the pipeline can only create bounded roles."
  type        = string
}
