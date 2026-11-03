# ADR-003: One shared container registry for all environments

- Status: Accepted
- Date: 2026-11-03
- Deciders: Abdu (Platform Engineer), mentor review

## Context

Nine services (eight backend services and `pharma-ui`) are built into container images. The reference POC created a separate set of ECR repositories in every environment (finding B2), with mutable tags, no customer managed encryption, and a lifecycle rule that expired any image beyond the newest ten.

Today dev, qa and prod share one AWS account (ADR-002 accepted risk). In a regulated (GxP) setting we must be able to show that the exact artifact tested in QA is the one running in production.

## Options

| Option | Isolation | Same artifact in every environment | Cost and upkeep |
|---|---|---|---|
| **A. Repositories per environment** (POC) | Only by name: IAM in one account can reach all of them | No: rebuild per environment, or copy images between repositories | 27 repositories |
| **B. One set of repositories in this account, shared by all environments** | Push limited to CI roles; environments only pull | Yes: build once, promote by digest | 9 repositories |
| **C. Central registry in a dedicated artifacts account** | Strong: separate account, cross-account pull only | Yes | Needs AWS Organizations and more accounts |

## Decision

Choose **B now**, built so that **C** is a later move, not a redesign.

- A `shared/` stack with its own state key (`shared/terraform.tfstate`), applied by the pipeline like `envs/dev`.
- Nine repositories named `zen-pharma/<service>`, created from one set with `for_each`.
- `IMMUTABLE` tags, scan on push (ECR basic scanning), encryption with a customer managed KMS key (`alias/zen-pharma-ecr`, rotation on).
- Lifecycle: expire **untagged** images 7 days after push; tagged images are never deleted automatically, because one may be running in an environment.
- Only CI pushes (ZPP-28); environments pull. Deployments reference images by digest.

When production moves to its own account, the repositories move to an artifacts account and gain a repository policy that grants pull to the environment accounts.

## Consequences

- Build once, deploy many: one digest flows from dev to qa to prod, which gives change-control evidence for free.
- A tag can never be overwritten, so a tag always means the same image.
- Push permissions are not separated per environment; the CI push role (ZPP-28) is scoped to these nine repositories only.
- Basic scanning covers OS packages on push only. Build-time Trivy scans (ZPP-5) cover language packages; continuous rescanning (Amazon Inspector or scheduled Trivy) is decided in ZPP-9.
- The `shared` stack uses the `dev` GitHub environment as its approval gate until qa and prod get their own gates (ZPP-8).
- Cost: about $1 per month for the KMS key, plus image storage.

## Sources

Checked **2026-11-03**:

- [Amazon ECR: Image tag mutability](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-tag-mutability.html)
- [Amazon ECR: Lifecycle policies](https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html)
- [Amazon ECR: Encryption at rest](https://docs.aws.amazon.com/AmazonECR/latest/userguide/encryption-at-rest.html)
- [Amazon ECR: Image scanning](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning.html)
