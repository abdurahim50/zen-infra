# ADR-000: Architecture baseline for Zen Pharma Platform

- Status: Accepted
- Date: 2026-10-23
- Deciders: Abdu (Platform Engineer), mentor review
- Ticket: ZPP-15

## Context

Zen Pharmaceuticals needs one platform to manage its drug catalogue, inventory, suppliers, manufacturing, and quality control records. An earlier prototype showed that the design works, with nine services running on EKS, deployed through GitOps, and connected to one PostgreSQL database.

An architecture review found 12 blockers, 19 security issues, and several differences between the documentation and the code. We are building the platform from scratch using enterprise practices.

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
| qc-service | Quality control testing of batches | Java 17, Spring Boot | 8086 | H2 in-memory today; must move to PostgreSQL (ZPP-4) |
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

We will use four repositories, nine services, EKS, RDS, ArgoCD, and Helm as our starting architecture, with these rules:

- We will not use long-lived AWS access keys. CI will use GitHub OIDC, and team members will use IAM Identity Center. The account will have no IAM users with access keys.

- Production changes will require a promotion pull request and a manual sync in ArgoCD. A commit alone will not deploy changes to production.

- Every review finding, including B1 to B12, S1 to S19, and differences between the documentation and code, must be fixed or have its risk formally accepted before go-live. Each finding will be included in the acceptance criteria for its related epic.

- qc-service will store its data in PostgreSQL so quality control records are preserved after restarts.

- All incoming API requests will go through pharma-ui, and AWS resources will be restricted to us-east-1.

- Development, QA, and production will share one AWS account to help keep spending within our $30 monthly budget.

## Consequences

Benefits

- CI will use temporary AWS credentials instead of a stored access key, reducing the risk of exposing a long-lived key.

- Deployment changes will be tracked in Git, so we can see who changed what and revert to an earlier configuration when needed.

- One shared Helm chart will let us define common security settings once and apply them to all nine services.

- Fixing issues during development should take less time and cost less than fixing them after go-live.

Tradeoffs and risks

- Sharing one AWS account means a mistake in development could affect production. We accept this risk to control costs and will reconsider separate accounts if our budget allows.

- All services will depend on one PostgreSQL database, so a database outage could affect the entire platform. Each service will have its own schema, but this will not protect it from a shared database outage.

- A mistake in the shared Helm chart could affect all nine services, so chart changes will need careful review.

- EKS and NAT gateways cost money while running. We will remove non-essential resources after each session to manage spending.

- Following enterprise practices will require more setup, review, and testing, which will slow progress within each sprint.

## Questions

- Service ports must have one source of truth and the docs must be generated or checked from the code. During review the documented ports for supplier-service, manufacturing-service and notification-service did not match the code (correct: 8084, 8085, 3000).
- qc-service must store QC records in PostgreSQL. An in-memory database loses every record on restart, which is not acceptable for pharma quality records (ZPP-4).
- notification-service must escape message text before putting it into email HTML, or send plain text only, to prevent HTML injection in emails (S19, ZPP-4).
- notification-service: SMS is not implemented yet. Decide whether we need it or remove it from scope.
- Frontend CI must use the same promotion path as the backend: dev automatically, then qa and prod through promotion PRs, never straight from main to prod (S8, ZPP-6).
- The API must have one entry point (through pharma-ui), not a second public ingress straight to api-gateway (ZPP-7).
- The JWT should not live in browser localStorage, where an XSS bug could steal it. Evaluate an HttpOnly cookie (ZPP-4).
