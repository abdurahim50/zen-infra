# -----------------------------------------------------------------------------
# RDS PostgreSQL (ZPP-36)
#
# - The master password is created, stored and rotated by RDS in Secrets
#   Manager (manage_master_user_password). Terraform never handles it, so it
#   is never in variables, plan output or state.
# - Storage and the password secret are encrypted with a customer managed key.
# - Only the EKS cluster security group may connect, on 5432; no outbound rules.
# - TLS is required for every connection (rds.force_ssl).
# - IAM database authentication is on, so pods can later log in with short-lived
#   tokens through EKS Pod Identity instead of a password.
# -----------------------------------------------------------------------------

# ---------- Encryption key (storage and the master password secret) ----------

resource "aws_kms_key" "rds" {
  description             = "${var.name} RDS storage and master password encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.name}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

# ---------- Network ----------

resource "aws_db_subnet_group" "this" {
  name        = "${var.name}-postgres"
  description = "Database tier subnets for ${var.name}"
  subnet_ids  = var.database_subnet_ids
}

# No egress rules: Terraform removes the default allow-all egress rule, and a
# database never needs to open outbound connections.
resource "aws_security_group" "rds" {
  name        = "${var.name}-postgres"
  description = "PostgreSQL: inbound 5432 from the EKS cluster only"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-postgres" }
}

resource "aws_vpc_security_group_ingress_rule" "from_eks" {
  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL from the EKS cluster security group"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = var.allowed_security_group_id
}

# ---------- Parameters: TLS required, connections logged ----------

resource "aws_db_parameter_group" "this" {
  name        = "${var.name}-postgres${split(".", var.engine_version)[0]}"
  family      = "postgres${split(".", var.engine_version)[0]}"
  description = "${var.name}: TLS required, connections logged"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_connections"
    value = "all"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------- Logs ----------

# RDS writes to this exact name. Creating it first means we set the retention;
# otherwise RDS creates it with "never expire".
resource "aws_cloudwatch_log_group" "postgresql" {
  name              = "/aws/rds/instance/${var.name}-postgres/postgresql"
  retention_in_days = var.log_retention_days
}

# ---------- Database ----------

resource "aws_db_instance" "this" {
  identifier     = "${var.name}-postgres"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  # Pinned version: minor upgrades happen by pull request, not silently.
  auto_minor_version_upgrade = false

  allocated_storage = var.allocated_storage_gb
  storage_type      = "gp3"
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  db_name                       = var.database_name
  username                      = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.rds.arn

  iam_database_authentication_enabled = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period   = var.backup_retention_days
  copy_tags_to_snapshot     = true
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-postgres-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]
  apply_immediately               = true

  depends_on = [aws_cloudwatch_log_group.postgresql]
}
