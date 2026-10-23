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

## The 9 services

| Service | Language | Port | Data |
| --- | --- | --- | --- |

## One request, browser to database

## Decision

## Consequences

## Questions
