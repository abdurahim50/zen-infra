# ADR-005: RDS PostgreSQL design for the dev environment

- Status: Accepted
- Date: 2026-11-08
- Deciders: Platform Engineering

## Context

The Zen Pharma services store their data in PostgreSQL. Sprint 3 builds the first database in `envs/dev`, in the database tier of the VPC from ADR-001, reachable from the EKS cluster from ADR-004.

This ADR records decisions made and verified during ZPP-36 (zen-infra PRs #19, #20, #21). The instance class, availability, dev backup settings, and password and authentication approach (decisions 1, 2, 3, 4 and 6) were chosen during that work; the rest follow from them and from ADR-002 and ADR-004. The ADR was written after the code merged; the Definition of Done now requires a merged ADR before the code PR for any ticket that adds a new AWS service.

Common risks this design avoids: a database password passed to Terraform as a variable (even marked `sensitive`, Terraform redacts it in plan output but stores it in plain text in state and saved plan files, so anyone who can read state can read it); automated backups turned off in non-production environments; storage on the AWS managed key instead of a customer managed key; and unrestricted outbound traffic from the database security group.

Constraints:

- Budget of $30 a month for the whole account (`zpp-monthly`, ZPP-14); dev is applied, tested and destroyed in the same session.
- Pipeline applies run as `zen-infra-apply` with the workload permissions boundary (ADR-002).
- The repository is public: no credentials, account ID or personal data in code, plan comments or logs.

## Decisions

### 1. Master password

| Option | Password in Terraform state? | Rotation |
|---|---|---|
| **A. RDS-managed (`manage_master_user_password`)** (chosen) | No: RDS creates it in Secrets Manager | Managed by RDS |
| B. `random_password` + `aws_secretsmanager_secret` | Yes, in plain text in state | Ours to build |
| C. Write-only `password_wo` with an ephemeral value | No, but Terraform still generates and handles it | Ours to build |

Chosen: **A**, with `master_user_secret_kms_key_id` set to our customer managed key so the secret is not on the AWS managed key.

Reason: RDS generates and rotates the master password, so Terraform never handles its value; applications will not use it, because IAM database authentication (decision 2) gives each service short-lived tokens for its own least-privilege user.

No password is readable from state or saved plans.

### 2. How applications log in

| Option | Notes |
|---|---|
| **A. IAM database authentication through EKS Pod Identity** (chosen) | Pods get a 15-minute token for a dedicated database user; no password stored for apps |
| B. Password from Secrets Manager via External Secrets | Works with any client, but a long-lived password sits in a Kubernetes secret |

Chosen: **A**. `iam_database_authentication_enabled = true` now; the `rds-db:connect` policy (scoped by the instance `resource_id` output) and the database users come with ZPP-37 and later tickets. The master user is for administration only, never for applications.

AWS states that IAM database authentication needs 300 to 1,000 MiB of extra memory on the instance for reliable connectivity. db.t4g.micro has 1 GiB in total, so it stays the initial dev choice but is not yet shown to be large enough. ZPP-37 must prove it: connect from a pod through Pod Identity as a service-specific database user, run the expected connection pool, and record freeable memory before and after. If headroom is too low, move to db.t4g.small (decision 4).

### 3. Availability

| Option | Notes | Approx. cost per hour |
|---|---|---|
| **A. Single-AZ in dev, Multi-AZ in prod** (chosen) | `multi_az` is a module variable, default `false` | $0.016 (db.t4g.micro) |
| B. Multi-AZ everywhere | Standby in a second AZ, automatic failover | about double |

Chosen: **A**. Dev is destroyed after each session, so a standby adds cost without adding anything we test.

### 4. Instance class

| Option | vCPU / memory | Approx. cost per hour |
|---|---|---|
| **A. db.t4g.micro** (chosen) | 2 / 1 GiB, Graviton (Arm) | $0.016 |
| B. db.t3.micro | 2 / 1 GiB, Intel | $0.018 |
| C. db.t4g.small | 2 / 2 GiB | $0.032 |

Chosen: **A**. The operator confirmed on 2026-11-08 that us-east-1 offers PostgreSQL 18.6 on db.t4g.micro (`aws rds describe-orderable-db-instance-options --engine postgres --engine-version 18.6 --db-instance-class db.t4g.micro --region us-east-1`), and the dev apply created the instance with that combination. The pinned values are in `envs/dev/main.tf` (`engine_version`) and `modules/rds/variables.tf` (`instance_class` default). Burstable is fine for dev test sessions; prod sizing is decided with load data. `instance_class` is a module variable. Open risk: memory headroom once IAM authentication is in use (decision 2).

### 5. Version and upgrades

| Option | Notes |
|---|---|
| **A. PostgreSQL 18.6 pinned, `auto_minor_version_upgrade = false`** (chosen) | Planned upgrades are reviewed by pull request; RDS can still apply a minor upgrade for a critical security issue or when a version reaches end of support |
| B. Auto minor upgrades on | Patches arrive in the maintenance window without review |

Chosen: **A**, in us-east-1. The parameter group family is derived from the major version (`postgres18`), so a major upgrade changes the family in the same pull request.

### 6. Deletion protection, snapshots and backups

The module defaults protect against accidental deletion and keep automated backups enabled; production retention is set by the production recovery requirement. Dev overrides the defaults explicitly in `envs/dev/main.tf`:

| Setting | Module default | Dev |
|---|---|---|
| `deletion_protection` | `true` | `false` (destroyed every session) |
| `skip_final_snapshot` | `false` | `true` (snapshots would pile up) |
| `backup_retention_period` | 1 day minimum, validated 1 to 35 | 1 day |

Automated backups are never off: dev keeps one day. The setting is verified (a latest restorable time was present); a restore has not been tested yet. A restore test records the restore time and checks a known row on the restored instance before teardown; it is planned with operational readiness (ZPP-10). A new environment that forgets to set these values gets deletion protection, a final snapshot and backups by default.

### 7. Network access

- Database subnets only (no route to the internet), `publicly_accessible = false`.
- One inbound rule: TCP 5432 from the **EKS cluster security group**, which EKS attaches to managed nodes. No CIDR rules. The ticket said "node security group"; the cluster security group is the one the nodes actually carry.
- No outbound rules: the current workload requires no database-initiated outbound connections. Revisit if a feature needs one (for example an extension that calls an external service).

### 8. Encryption, TLS and logging

- Storage and the master password secret encrypted with one customer managed KMS key (`alias/<name>-rds`, rotation on, 7-day deletion window).
- Parameter group with `rds.force_ssl = 1`. RDS for PostgreSQL 15 and later already defaults this to 1, so setting it makes TLS enforcement explicit in code and protects it from a parameter group change; a non-TLS connection was refused in testing.
- `log_connections = all` and `log_disconnections = 1` (PostgreSQL 18 changed `log_connections` from on/off to a list; PR #20).
- The parameter group uses `name_prefix` with `create_before_destroy`, so a replacement does not collide with the old group (PR #21).
- PostgreSQL log exported to CloudWatch; the log group is created by Terraform first so retention is 7 days, not "never expire".

## Cost and operating model

| Item while running | Approx. per hour |
|---|---|
| db.t4g.micro, single-AZ | $0.016 |
| 20 GiB gp3 storage | about $0.003 |
| KMS key, Secrets Manager secret, logs | about $0.003 |
| **Total** | **about $0.02** |

RDS adds about 15 minutes to an apply and about $0.25 a week at the current test rhythm. Within the $30 budget with the EKS costs from ADR-004.

## Consequences

- No database password exists in the repository, variables, plan output or state; verified by searching the whole state.
- Applications need IAM-auth-capable clients and a database user per service; that work lands with Pod Identity.
- db.t4g.micro may be too small once IAM authentication is used; ZPP-37 measures it.
- Reading the master password for administration needs `secretsmanager:GetSecretValue` and `kms:Decrypt` on our key; it is read into a shell variable, never printed.
- Minor versions fall behind until someone raises a pull request; reviewed at each sprint review. RDS may still force a minor upgrade (critical security fix or end of support), and the code is then updated to match.
- Dev data does not survive a destroy; there is no data worth keeping in dev.

## Verification

The following ZPP-36 checks passed on 2026-11-08 in us-east-1; results are in the [post-merge verification comment on zen-infra PR #19](https://github.com/abdurahim50/zen-infra/pull/19#issuecomment-6728771114):

- State holds `password: null` and no password values.
- TLS connection from a pod works (`pg_stat_ssl.ssl = t`); a non-TLS connection is refused.
- The endpoint resolves to a private address and 5432 is unreachable from outside the VPC.
- One inbound rule from the cluster security group; no outbound rules.
- Storage and secret on the customer managed key; backup retention 1 day (setting only, restore not yet tested); logs 7 days.

Pending:

- ZPP-37: a pod logging in through Pod Identity as a service-specific database user, and memory headroom on db.t4g.micro under the expected connection pool (pool size, duration and pass/fail threshold set in the ticket before the test).
- ZPP-10: a restore test (restore time recorded, known row checked on the restored instance).

## Control mapping (mapped, not certified)

| Decision | NIST SP 800-53 | DoD CIO Cloud Security Playbook |
|---|---|---|
| RDS-managed password, no secret in state | IA-5, SC-28 | Play 14 (secrets management) |
| IAM database authentication via Pod Identity (**planned** for verification in ZPP-37) | IA-2, AC-6 | Play 7 (identity and access management) |
| Database subnets, cluster SG only, no egress | SC-7, AC-4 | Play 16 (network segmentation) |
| Customer managed KMS key for storage and secret | SC-28, SC-12 | Play 13 (encrypt data at rest), Play 14 (key management) |
| TLS required | SC-8 | Play 13 (encrypt data in transit) |
| Connection logging with retention | AU-2, AU-11, AU-12 | Play 10 (logging) |
| Automated backups always on (restore test pending) | CP-9 | Play 17 (cyber resiliency: automated backups) |
| Protective defaults, pinned version, upgrades by PR | CM-2, CM-3, SI-2 | Play 6 (infrastructure as code) |

## Sources

Checked **2026-11-08**:

- [Amazon RDS: password management with Secrets Manager](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-secrets-manager.html)
- [Amazon RDS: IAM database authentication](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.html)
- [Amazon RDS: SSL/TLS with PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Concepts.General.SSL.html)
- [Amazon RDS: Multi-AZ deployments](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZ.html)
- [Amazon RDS: PostgreSQL versions](https://docs.aws.amazon.com/AmazonRDS/latest/PostgreSQLReleaseNotes/postgresql-versions.html)
- [Amazon RDS: upgrading the PostgreSQL engine](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_UpgradeDBInstance.PostgreSQL.html)
- [Amazon EKS: security group requirements](https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html)
- [PostgreSQL 18: error reporting and logging](https://www.postgresql.org/docs/18/runtime-config-logging.html)
- DoD CIO Cloud Security Playbook, Volume 1 (play numbers from its table of contents and Top Mitigation Strategies list)
- [Terraform: sensitive data in state](https://developer.hashicorp.com/terraform/language/manage-sensitive-data)
- [Terraform: aws_db_instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance)
- [Terraform: aws_db_parameter_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_parameter_group)
- [Amazon RDS for PostgreSQL pricing](https://aws.amazon.com/rds/postgresql/pricing/)
