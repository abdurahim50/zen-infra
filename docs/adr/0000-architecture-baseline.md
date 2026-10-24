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
| zen-pharma-backend | Source code for the 8 API services: api-gateway, auth, drug-catalog, inventory, supplier, manufacturing and qc (Java 17, Spring Boot) and notification (Node.js, Express). One CI pipeline per service, built from shared reusable workflows: build, unit tests with coverage, SAST (CodeQL, Semgrep), dependency scan, Docker build, Trivy image scan, push to ECR, Cosign signature, then a commit that updates the image tag in zen-gitops. | Container images in Amazon ECR. CI never deploys: ArgoCD deploys from zen-gitops (develop branch to dev automatically, qa and prod through promotion PRs). |
| zen-pharma-frontend | Source code for pharma-ui: a React single-page app, built and served by nginx (unprivileged, port 8080), which also proxies /api/ to api-gateway. CI: lint, unit tests, build, Docker image, scan, push to ECR, then update the pharma-ui image tag in zen-gitops. | Container image in Amazon ECR, deployed by ArgoCD from zen-gitops like the backend. |

## The 9 services

| Service | Purpose | Language | Port | Data |
| --- | --- | --- | --- | --- |
| api-gateway | Single entry point for /api traffic; routes each request to the right service and checks the JWT | Java 17, Spring Cloud Gateway | 8080 | none |
| auth-service | Login, JWT issuing, user management | Java 17, Spring Boot | 8081 | PostgreSQL, schema `auth` |
| drug-catalog-service | Drug catalogue: search, categories, formulary | Java 17, Spring Boot | 8082 | PostgreSQL, schema `drug_catalog` |
| inventory-service | Stock levels, replenishment, batch tracking | Java 17, Spring Boot | 8083 | PostgreSQL, schema `inventory` |
| supplier-service | Suppliers and purchase orders | Java 17, Spring Boot | 8084 | PostgreSQL, schema `procurement` |
| manufacturing-service | Production orders and batch manufacturing | Java 17, Spring Boot | 8085 | PostgreSQL, schema `manufacturing` |
| qc-service | Quality control testing of batches | Java 17, Spring Boot | 8086 | H2 in-memory (POC only; data lost on every restart) |
| notification-service | Email notifications through SMTP (SMS only logged, not sent) | Node.js, Express | 3000 | none |
| pharma-ui | React web app served by nginx; proxies /api/ to api-gateway | React, nginx (unprivileged) | 8080 | none |

## One request, browser to database

1. When I log in, the React app in my browser sends my username and password to `/api/auth/login` over HTTPS.
2. The request reaches the AWS NLB, which forwards it to ingress-nginx inside the EKS cluster.
3. Ingress-nginx routes the request to pharma-ui. Its nginx recognizes `/api/` and forwards it to the internal api-gateway Service.
4. The Service directs the request to an api-gateway pod, which routes `/api/auth/login` to auth-service.
5. The gateway allows login without a JWT because the user needs to log in before receiving one.
6. Auth-service checks the user's record in the PostgreSQL `auth` schema and verifies the password against the stored hash. RDS sits in a private subnet, and its security group only allows port 5432 from the EKS nodes. Its database credentials come from a Kubernetes Secret populated by ESO from AWS Secrets Manager; ESO reads Secrets Manager through an IAM role (IRSA), so no AWS keys exist in the cluster.
7. If the credentials are correct, auth-service creates a signed JWT and sends it back through the same components to the browser.
8. For later protected API requests, the browser includes the JWT in the Authorization header, and api-gateway validates it before forwarding the request.

## Decision

## Consequences

## Questions

- Docs drift: backend README lists supplier 8085, manufacturing 8084, notification 8086. Code says 8084, 8085, 3000. Code wins.
- qc-service uses H2 in-memory: QC records lost on restart. Must move to Postgres (ZPP-4).
- notification-service puts the message into email HTML without escaping: possible HTML injection in emails. Review in ZPP-4.
- notification-service: SMS is not implemented, only logged.
- POC frontend CI wrote every push to main straight into the prod values file (S8): no QA step, no manual gate. Our build uses the same promotion path as the backend (ZPP-6).
