# ADR-002: GitHub Actions access to AWS with OIDC

- Status: Accepted
- Date: 2026-11-02
- Deciders: Abdu (Platform Engineer), mentor review

## Context

The Terraform pipeline (ZPP-26) must plan and apply infrastructure from GitHub Actions. The reference POC authenticated its Terraform pipeline with static AWS access keys stored as GitHub secrets, and keys of that kind leaked during onboarding (ZPP-17). We will not store long-lived AWS credentials in GitHub.

Findings that shaped the design:

- The AWS account already held a GitHub OIDC provider and three roles from an earlier project (MediBook), last used by an automated dependency-update pull request. That project moves to its own AWS account, so its provider and roles were deleted and this account belongs to Zen Pharma only.
- Our repositories send **immutable subject claims**: the token subject contains the owner and repository IDs (`repo:OWNER@OWNER_ID/REPO@REPO_ID:...`), not just the names. A trust policy written for the documented default format would never match. We confirmed the format with `gh api repos/abdurahim50/zen-infra/actions/oidc/customization/sub` before writing any policy.
- The pipeline role must create IAM roles for workloads (VPC flow logs now; EKS, node groups and IRSA in Sprint 3). A role that can create roles can create one more powerful than itself unless that is prevented.

## Options

| Option | Security | Effort |
|---|---|---|
| **A. Static access keys in GitHub secrets** | Long-lived keys that can leak and must be rotated by hand. Rejected: this is the POC's failure. | Low |
| **B. OIDC, one role with AdministratorAccess** | No stored keys, but any workflow that can assume the role controls the whole account, including its own permissions. | Low |
| **C. OIDC, separate plan and apply roles, scoped permissions, a permissions boundary and explicit denies** | No stored keys; pull requests get read-only access; apply needs an approval and cannot raise its own access. | Medium |

## Decision

Choose **C**. Everything lives in the `bootstrap` stack, which a human applies from a laptop after review. The pipeline never applies `bootstrap`; if it could, it could change its own permissions.

1. **One GitHub OIDC provider per account** (`token.actions.githubusercontent.com`, audience `sts.amazonaws.com`), owned by `bootstrap`.
2. **`zen-infra-plan`**, trusted only for pull requests in `zen-infra` (exact subject match on the immutable IDs). Permissions: `ReadOnlyAccess`, read access to pipeline state (`envs/*`, `shared/*`) and write access only to the `.tflock` lock objects.
3. **`zen-infra-apply`**, trusted only for jobs in the `dev` GitHub environment. The environment's protection rules (required reviewer, `main` only) are the approval gate, and AWS enforces it because only an approved job receives that subject.
4. **Apply permissions, four layers:**
   - **Allow** the services our stacks use (EC2/VPC, CloudWatch Logs, ECR, KMS, EKS, RDS, Secrets Manager, Elastic Load Balancing, Auto Scaling), in `us-east-1` only, plus read and write access to pipeline state.
   - **IAM limited to `zen-pharma-*`**: create or change roles only when they carry the workload boundary; pass roles only to named AWS services; create only named service-linked roles and EKS OIDC providers.
   - **Workload boundary** (`zen-pharma-workload-boundary`): the ceiling for every role the pipeline creates. No IAM writes, no Organizations or account changes, no access to Terraform state or its key.
   - **Explicit denies**, which beat any allow: no changes to the CI roles, the GitHub provider or the boundary; no removing a boundary; no IAM users, access keys or console passwords; no changes to the state bucket configuration, bootstrap state, state history or the state KMS key; no Organizations or account actions.
5. **GitHub owner and repository IDs stay out of this public repository.** They come from git-ignored `terraform.tfvars`, the same rule we apply to the AWS account ID.

## Consequences

- **No AWS keys exist in GitHub.** Credentials last at most one hour and are tied to one workflow job.
- **Role creation cannot escalate privilege.** The apply role may create a role only if it carries the workload boundary, so attaching `AdministratorAccess` to a new role still leaves it capped by the boundary. Verified with `aws iam simulate-principal-policy`: creating a role without the boundary is denied, with it allowed.
- **The pipeline cannot raise its own access.** Explicit denies stop the apply role from editing its own policies or trust policy, the plan role, the GitHub provider or the boundary. Verified: `iam:UpdateAssumeRolePolicy` and `iam:PutRolePolicy` on `zen-infra-apply` return `explicitDeny`.
- **Terraform state is protected from the pipeline it serves.** Deleting the bucket, changing its policy, versioning or encryption, deleting state versions, writing bootstrap state or scheduling the key for deletion all return `explicitDeny`.
- **Every pipeline-created role needs the boundary**, so modules that create roles take a required `permissions_boundary_arn` input (the VPC flow logs role first).
- Changes to `bootstrap` remain manual and need a reviewed pull request first.

### Accepted risks (dev)

| Risk | Why accepted now | Follow-up |
|---|---|---|
| Service-wide actions (`ec2:*`, `eks:*`, `rds:*`, `secretsmanager:*` and others) for the apply role | Region-locked, capped by the denies and the approval gate; the Sprint 3 resource set is not final | Narrow to the actions used, generated from CloudTrail with IAM Access Analyzer, after Sprint 3 |
| `ReadOnlyAccess` on the plan role can read data across the account, including S3 objects | Dev holds no patient or production data | Replace with a listed set of read actions after Sprint 3 |
| Whoever can push a branch controls the pull request workflow, so they can run any command with the plan role | Inherent to pull request plans; the role is read-only and fork pull requests get no token | Keep repository write access limited |
| The plan role can delete `.tflock` objects and so break a running lock | Disruption, not escalation; workflow `concurrency` (ZPP-26) prevents overlapping runs | None |
| Pull request plans can read pipeline state | State must not contain secrets | Sprint 3: RDS-managed master password, write-only or ephemeral arguments; proof that state holds no passwords |
| One person approves their own apply | Solo project | A team would enable "prevent self-review" with a second reviewer |
| Dev and the target production share one account in this project | Budget | Production belongs in a separate account under AWS Organizations |
| The AWS account ID appears in 2 historical commits and PRs #4 to #6 (made public Nov 2026 without a history rewrite) | An account ID is not a credential; a rewrite would break SHAs and still leave PR refs | None; every new commit follows POL-02 |
| The dev apply job plans and applies after approval, so it can differ from the plan reviewed on the pull request if main changed in between | Dev only; the plan is printed in the apply log before it runs | Production: separate plan job, reviewed plan artifact stored privately |

## Sources

Checked **2026-11-02**:

- [GitHub Docs: Configuring OpenID Connect in Amazon Web Services](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws)
- [GitHub Docs: OpenID Connect reference (subject claims)](https://docs.github.com/en/actions/reference/security/oidc)
- [AWS IAM: Permissions boundaries for IAM entities](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html)
- [AWS IAM: Policy evaluation logic (explicit deny)](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html)
