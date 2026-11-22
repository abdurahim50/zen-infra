# ADR-006: Container image standard

- Status: Accepted
- Date: 2026-11-22
- Deciders: Platform Engineering

## Context

The platform runs nine services as containers: seven Java (Spring Boot) services, one Node.js service and one web front end served by Nginx. Their images are pushed to the shared ECR repositories from ADR-003 by the CI push role, and will later run on the EKS cluster from ADR-004.

This ADR sets one standard for every image, so each Dockerfile is reviewed against the same rules. It is written before any service code or Dockerfile, as the Definition of Done requires.

Common risks this standard avoids:

- Images built on mutable tags (a tag can be moved to point at a different image).
- Runtime images that carry a shell and package manager the services do not need.
- A Dockerfile that creates a non-root user but never switches to it, so the process still runs as root.
- Runtimes or frameworks past end of life, which receive no security fixes.
- Environment files committed to source control and copied into images.

Constraints:

- Budget of $30 a month for the whole account; image work runs locally and in GitHub Actions, not on AWS compute.
- Repositories go public: no credentials, account ID or personal data in Dockerfiles, build arguments, image layers or CI logs.
- Every security gate is enforced in code (CI and Kubernetes admission later), not by convention.

## Decisions

### 1. Runtime base images

| Option | Shell and package manager | Notes |
|---|---|---|
| A. Docker Official images (`eclipse-temurin` JRE, `node` slim, `nginx`) | Yes | Easy to debug; larger; more CVEs to triage |
| **B. Distroless for Java and Node, unprivileged Nginx for the web tier** (chosen) | No (Nginx image: minimal Alpine) | Smaller attack surface; debug with ephemeral containers |
| C. Chainguard images | No | Fewest CVEs; the free tier gives only `latest`, so no version-line pin |

Chosen: **B**.

| Runtime | Runtime image | Build stage image |
|---|---|---|
| Java (7 services) | `gcr.io/distroless/java21-debian13:nonroot` | Official Maven image on Eclipse Temurin 21 |
| Node.js (notification) | `gcr.io/distroless/nodejs24-debian13:nonroot` | Official `node` 24 image |
| Web front end | `nginx/nginx-unprivileged` (stable, Alpine) | Official `node` 24 image |

Notes:

- Distroless publishes Debian 13 images only; other tags are deprecated and no longer updated.
- `nginx/nginx-unprivileged` replaced the older `nginxinc` namespace. It listens on 8080 and is also published on Amazon ECR Public (`public.ecr.aws/nginx/nginx-unprivileged`).
- Java 21 and Node.js 24 are both long-term support lines (decisions 8 and 9).
- Health checks: Kubernetes uses liveness and readiness probes from the pod spec, so images do not need a shell for a `HEALTHCHECK`. The local compose test checks endpoints from a separate container.
- Debugging uses `kubectl debug` with an ephemeral container, never a shell baked into the image.

### 2. Pinning

| Option | Immutable | Readable |
|---|---|---|
| A. Tag only (`nginx:1.29-alpine`) | No | Yes |
| **B. Tag plus digest (`image:tag@sha256:...`)** (chosen) | Yes | Yes |
| C. Digest only | Yes | No |

Chosen: **B**, for every `FROM` line, build stages included. This matches how the repositories already pin GitHub Actions by commit SHA and the Trivy binary by checksum. Digests change only through a reviewed pull request (decision 6).

### 3. Runtime hardening

| Option | Notes |
|---|---|
| A. Non-root user only | Leaves a writable filesystem and default capabilities |
| **B. Numeric non-root UID, read-only root filesystem, no capabilities, no privilege escalation** (chosen) | Enforced locally in compose now, in the Kubernetes `securityContext` later |

Chosen: **B**:

- `USER` is a number, not a name: 65532 for distroless (`nonroot`), the image's own UID for Nginx. Kubernetes `runAsNonRoot` can verify a numeric UID; it cannot verify a user name. Both UIDs are proven with `docker inspect` during the build, not assumed.
- Application files are copied with `--chown` to that UID and are not writable by it.
- Root filesystem read-only; `/tmp` (and the Nginx cache and PID paths) on `tmpfs`.
- All Linux capabilities dropped; `no-new-privileges` set.
- Services listen on ports above 1024 (8080 to 8086, 3000), so no capability is needed to bind.
- No secrets, credentials or environment files in any layer or build argument. Runtime configuration comes from environment variables; secrets come from AWS at runtime (ADR-005, External Secrets later).

These settings line up with the Kubernetes Pod Security Standards "restricted" profile, which the cluster will enforce in a later ticket.

### 4. Vulnerability gate and exceptions

| Option | Notes |
|---|---|
| A. Fail on CRITICAL only | HIGH findings with a fix ship unnoticed |
| **B. Fail on CRITICAL and HIGH where a fix exists** (chosen) | Blocks what can be fixed now |
| C. Report only | No gate |

Chosen: **B**. Trivy (the version already pinned in CI) scans every image with `--severity CRITICAL,HIGH --ignore-unfixed --exit-code 1`.

Exceptions:

- Live in `.trivyignore.yaml` next to the Dockerfile, passed with `--ignorefile`.
- Each entry has the vulnerability `id`, a `statement` naming the ticket and the reason, and an `expired_at` date no more than 90 days out. After that date Trivy stops ignoring the finding and the build fails again, so no exception is permanent.
- The YAML ignore file is marked experimental by Trivy. The pinned Trivy version protects us from format changes; a Trivy upgrade PR must re-test the ignore file.
- Exceptions are reviewed at every sprint review.

### 5. Software bill of materials (SBOM)

| Option | Notes |
|---|---|
| **A. CycloneDX SBOM from Trivy for every image build now** (chosen) | Stored as a CI artifact; inventory exists from the first image |
| B. Wait for image signing work | No inventory until then |

Chosen: **A**. Signing images and attaching the SBOM as a signed attestation, and admission checks that verify them, are a later ticket (ZPP-41).

### 6. Base image updates

| Option | Notes |
|---|---|
| **A. Dependabot, `docker` ecosystem, weekly** (chosen) | Already enabled on the repositories; no new tool to trust |
| B. Renovate | More flexible; new third-party app with write access |
| C. Manual monthly check | Relies on memory |

Chosen: **A**. Each update arrives as a pull request that runs the same build and scan gate. Whether Dependabot raises PRs for digest-only changes on `tag@sha256` lines is to be confirmed in the first sprint; if it does not, a monthly digest refresh is added as a recurring ticket.

### 7. Where this standard lives

Chosen: here, in `zen-infra/docs/adr`, so the platform has one ADR sequence. The backend and frontend READMEs link to it. A Dockerfile that departs from this standard needs a new or superseding ADR, not a code comment.

### 8. Node.js version

Chosen: **Node.js 24** for the notification runtime and the front-end build stage. Node.js 20 reached end of life on 2026-04-30; Node.js 22 is supported only to April 2027.

### 9. Java and Spring Boot versions

Chosen: the services are written new on **Java 21** and on the newest **Spring Boot** line that has open source support when each service is started, confirmed on spring.io and recorded in the service README. No service starts on a framework line that is already out of open source support. Spring Boot is then kept current through Dependabot (`maven` ecosystem) pull requests, under the same build and scan gate.

## Cost and operating model

| Item | Cost |
|---|---|
| Builds and scans | GitHub Actions minutes (public repositories free; private repositories within the plan's included minutes) |
| ECR storage | Already covered by ADR-003; untagged images expire through the lifecycle rule |
| AWS compute | None: images are built and tested locally and in CI |

## Consequences

- No shell in Java and Node images: troubleshooting needs ephemeral debug containers and good logs.
- Every base update is a pull request, so image freshness depends on reviewing Dependabot PRs promptly.
- Builds fail on new fixable HIGH or CRITICAL CVEs even when the code did not change. This is intended.
- The front-end build tool is chosen when the front end is written; whatever it is, its output is served by the image in decision 1 and build-time values are non-secret build arguments, never a committed environment file.
- Images are not yet signed, and the cluster does not yet refuse unsigned or unscanned images. Until ZPP-41, the gate is the CI pipeline and the ECR push role.

## Verification

To be proven in ZPP-47, ZPP-48 and ZPP-49, with evidence in each ticket and a post-merge verification comment:

- Every `FROM` line has a tag and a digest (checked by a script in CI).
- `docker inspect` shows a numeric non-root `User` for all nine images; a running container reports that UID.
- Containers start and pass the compose smoke test with a read-only root filesystem, no capabilities and `no-new-privileges`.
- Trivy gate passes for all nine images; every ignore entry has a ticket, reason and expiry.
- A CycloneDX SBOM exists for every image.
- No environment file, credential or secret in any image layer (layer listing plus a secret scan of the image).

## Control mapping (mapped, not certified)

| Decision | NIST SP 800-53 | DoD CIO Cloud Security Playbook |
|---|---|---|
| Minimal runtime images, no shell | CM-7 | Play 19 (secure containers: hardening) |
| Tag plus digest pinning, updates by PR | CM-2, CM-3, SR-11 | Play 19 (immutable containers), Play 21 (third-party risk) |
| Numeric non-root UID, read-only filesystem, no capabilities | AC-6, CM-6 | Play 19 (no root, least privilege) |
| Vulnerability gate with dated exceptions | RA-5, SI-2 | Play 19 (scan; block by severity), Play 20 (pipeline control gates) |
| SBOM for every image | CM-8, SR-4 | Play 20 and Play 21 (automatic SBOM creation) |
| No secrets in images | IA-5, SC-28 | Play 19 (no embedded clear-text secrets) |
| No end-of-life runtimes or frameworks; kept current by PR | SA-22, SI-2 | Play 21 (third-party risk) |

## Sources

Checked **2026-11-22**:

- [Distroless images (supported images and tags)](https://github.com/GoogleContainerTools/distroless)
- [NGINX unprivileged image](https://github.com/nginx/docker-nginx-unprivileged)
- [Trivy: filtering, ignore files and `--ignore-unfixed`](https://trivy.dev/latest/docs/configuration/filtering/)
- [Trivy: SBOM output](https://trivy.dev/latest/docs/supply-chain/sbom/)
- [Dependabot: supported ecosystems](https://docs.github.com/en/code-security/dependabot/ecosystems-supported-by-dependabot/supported-ecosystems-and-repositories)
- [Kubernetes: Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Kubernetes: configure a security context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [Kubernetes: liveness, readiness and startup probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Kubernetes: debug with ephemeral containers](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/#ephemeral-container)
- [Docker Compose: services reference (`read_only`, `cap_drop`, `security_opt`, `tmpfs`)](https://docs.docker.com/reference/compose-file/services/)
- [Dockerfile reference (`USER`, `COPY --chown`)](https://docs.docker.com/reference/dockerfile/)
- [Node.js release schedule and end of life](https://nodejs.org/en/about/previous-releases)
- [Spring Boot: project page and support](https://spring.io/projects/spring-boot#support)
- DoD CIO Cloud Security Playbook, Volume 2: Play 19 (Secure Containers and Microservices), Play 20 (Defend DevSecOps Pipelines), Play 21 (Mitigate Third Party Risk)
