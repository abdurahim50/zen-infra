# zen-infra

Terraform for the Zen Pharma Platform AWS infrastructure (us-east-1).

## Layout

| Path | Purpose |
| --- | --- |
| `bootstrap/` | Creates the Terraform state bucket (run once) |
| `modules/` | Reusable modules (vpc, eks, rds, ...) |
| `envs/dev` (qa and prod added in ZPP-8) | One stack per environment, each with its own state |
| `docs/adr/` | Architecture decision records |
| `docs/runbooks/` | Operational runbooks |

## Standards

- Terraform `>= 1.10, < 2.0`, AWS provider `~> 6.0`, lock file committed
- Every resource gets default tags: Project, Environment, Owner, CostCenter, ManagedBy
- Real values go in `terraform.tfvars` (git-ignored); copy from `terraform.tfvars.example`
- Commits: `type(scope): summary (ZPP-n)`

## Local setup

```bash
pre-commit install
tflint --init
cd envs/dev && cp terraform.tfvars.example terraform.tfvars
terraform init -backend=false && terraform validate
```
