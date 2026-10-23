# ADR-000: Architecture baseline for Zen Pharma Platform

- Status: Proposed
- Date: 2026-10-23
- Deciders: Abdu (Platform Engineer), mentor review
- Ticket: ZPP-15

## Context

## The 4 repositories

| Repo | Owns | Deploys to |
| --- | --- | --- |
| zen-infra | All AWS infrastructure as Terraform code: VPC, EKS cluster, RDS PostgreSQL, ECR image repositories, IAM roles (including the GitHub OIDC role) and Secrets Manager entries. Shared modules hold the recipes; one folder per environment (envs/dev, envs/qa, envs/prod) holds its settings and its own state file in an encrypted, locked S3 bucket. | The AWS account (us-east-1), applied by a GitHub Actions pipeline after a PR is merged. |
| zen-gitops | The desired state of every environment: one shared Helm chart (pharma-service) used by all 9 services, one values file per service per environment (envs/dev, envs/qa, envs/prod) holding image tag, port and settings, the ArgoCD application definitions, and the External Secrets setup that pulls secrets from AWS Secrets Manager into the cluster. CI never deploys directly: it only changes a values file in Git, and ArgoCD running inside the cluster pulls that change (pull model). | The EKS cluster, applied by ArgoCD: dev syncs automatically, qa syncs after a promotion PR is merged, prod needs a promotion PR plus a manual sync. |

## The 9 services

| Service | Language | Port | Data |
| --- | --- | --- | --- |

## One request, browser to database

## Decision

## Consequences

## Questions
