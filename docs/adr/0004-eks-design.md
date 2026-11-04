# ADR-004: EKS design for the dev environment

- Status: Accepted
- Date: 2026-11-04
- Deciders: Abdu (Platform Engineer), mentor review

## Context

The nine Zen Pharma services run on Kubernetes. Sprint 3 builds the first Amazon EKS cluster in `envs/dev`, inside the three-tier VPC from ADR-001.

The reference POC's cluster (findings B4 and S13) gave admin only to the identity that created it, exposed the API endpoint to `0.0.0.0/0`, had no envelope encryption for Kubernetes secrets and no control-plane logs.

Constraints:

- Budget of $30 a month for the whole account (`zpp-monthly`, ZPP-14). EKS alone costs $0.10 an hour, about $73 a month if left running.
- The cluster is created by the pipeline (`zen-infra-apply`, GitHub-hosted runners), but people use `kubectl` from a laptop.
- The repository is public: no personal data (such as a home IP address) may appear in code, plan comments or logs.

## Decisions

### 1. Kubernetes version

| Option | Notes |
|---|---|
| **A. 1.37** (chosen) | Newest version in standard support; standard support ends 2027-12-01 |
| B. 1.36 | One version behind; standard support ends 2027-08-02 |

Chosen: **1.37** with `upgrade_policy { support_type = "STANDARD" }`. A cluster still on 1.37 after standard support ends is upgraded automatically instead of moving into paid extended support. That automatic upgrade covers the control plane only; node groups and add-ons are ours to upgrade, so we upgrade before the end date rather than relying on it.

### 2. Worker nodes

| Option | Memory per node | Pods per node (default VPC CNI) | Approx. cost per hour |
|---|---|---|---|
| **A. 2 x t3.medium, On-Demand** (chosen) | 4 GiB | 17 | $0.083 |
| B. 3 x t3.small + prefix delegation | 2 GiB | more IPs, same memory | $0.062 |
| C. 2 x t3.medium, Spot | 4 GiB | 17 | about 60 to 70% less |

Chosen: **A**, a managed node group in the private subnets, desired 2, minimum 2, maximum 3.

> "4 GiB per node gives the services and system pods more room, and I can test the dev cluster without Spot interruptions." (Abdu)

Spot (C) is revisited once workloads tolerate interruption (Sprint 4 or later).

### 3. API endpoint access

| Option | Notes |
|---|---|
| **A. Private and public endpoint, public restricted to one /32** (chosen) | Nodes use the private endpoint; `kubectl` works from the laptop without a bastion |
| B. Private endpoint only | Most restrictive; needs a bastion or VPN (SSM), more cost and setup |

Chosen: **A**.

> "Keep node traffic on the private endpoint and allow public access only from my current public IP (/32), so I can run kubectl from my laptop without maintaining a bastion." (Abdu)

- The allowed CIDR is a `sensitive` Terraform variable supplied by a GitHub secret, so it never appears in the repository, the public plan comment or logs.
- The pipeline does not need the Kubernetes API: access entries and Pod Identity associations are created through the AWS EKS API.
- When the home IP changes, update the secret and re-apply.

### 4. Cluster access

Chosen: **EKS access entries** (`authentication_mode = "API"`), no `aws-auth` ConfigMap.

- `bootstrap_cluster_creator_admin_permissions = false`: the pipeline role that creates the cluster does **not** become a Kubernetes admin.
- One access entry for the SSO admin role with `AmazonEKSClusterAdminPolicy`, cluster scope. Fixes POC finding B4.

### 5. Secrets encryption

Chosen: envelope encryption of Kubernetes secrets with a **customer managed KMS key** (rotation on, 7-day deletion window for dev). Fixes part of POC finding S13.

### 6. Control-plane logs

| Option | Notes |
|---|---|
| **A. audit + authenticator, 7-day retention** (chosen) | Who did what, and who authenticated; lowest cost |
| B. All five log types | More detail, larger CloudWatch bill |

The log group `/aws/eks/<cluster>/cluster` is created by Terraform **before** the cluster, so retention is set by us and not left at "never expire".

### 7. Pod access to AWS

| Option | Notes |
|---|---|
| **A. EKS Pod Identity** (chosen) | `eks-pod-identity-agent` add-on; trust `pods.eks.amazonaws.com`; no per-cluster OIDC provider; roles reusable across clusters |
| B. IRSA (POC) | Per-cluster OIDC provider; trust policy tied to the cluster's issuer URL |

Chosen: **A**. Pod roles are named `zen-pharma-*` and carry the `zen-pharma-workload-boundary` (ADR-002).

### 8. Node hardening

- IMDSv2 required, hop limit 1: pods (not on the host network) cannot reach the node's instance role.
- EBS root volumes encrypted.
- Node role carries the workload permissions boundary.
- Add-ons (`vpc-cni`, `coredns`, `kube-proxy`, `eks-pod-identity-agent`) managed by Terraform with pinned versions.

## Cost and operating model

| Item while running | Approx. per hour |
|---|---|
| EKS control plane | $0.100 |
| 2 x t3.medium | $0.083 |
| NAT gateway (ADR-001) | $0.045 |
| Public IPv4, EBS, logs | about $0.010 |
| **Total** | **about $0.24** |

Apply, test, destroy: about 12 cluster-hours a week, roughly $12 a month, plus about $1 a month per customer managed KMS key while it exists. Within the $30 budget, with `zpp-monthly` alerts at $15, $24 and $30.

## Consequences

- No identity gets cluster admin by accident, and the pipeline cannot use the cluster it creates.
- A changing home IP means updating one secret; acceptable for one engineer, replaced by private access for a team.
- Hop limit 1 means any add-on that reads instance metadata (for example the AWS Load Balancer Controller) must be given its region and VPC ID explicitly.
- 17 pods per node: two nodes are enough for the 9 services plus system pods in dev; Argo CD and External Secrets (Sprint 4) may need the third node or prefix delegation.
- Spot and private-only access are deferred, not rejected.

## Control mapping (mapped, not certified)

| Decision | NIST SP 800-53 | DoD CIO Cloud Security Playbook |
|---|---|---|
| Access entries, no creator admin | AC-2, AC-6 | Identity and access management |
| Endpoint restricted to one /32, private node traffic | SC-7, AC-17 | Apply network segmentation |
| KMS envelope encryption | SC-28, SC-12 | Play 13 (encrypt data at rest), Play 14 (secrets management) |
| audit + authenticator logs, retention set | AU-2, AU-11, AU-12 | Play 10 (set up logging) |
| Pod Identity, no static keys | IA-2, AC-6 | Play 14 (non-person entities) |
| Supported version, pinned add-ons | SI-2, CM-2 | |

## Sources

Checked **2026-11-04**:

- [Amazon EKS: Kubernetes version lifecycle](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
- [Amazon EKS: access entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html)
- [Amazon EKS: cluster endpoint access](https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html)
- [Amazon EKS: envelope encryption](https://docs.aws.amazon.com/eks/latest/userguide/envelope-encryption.html)
- [Amazon EKS: control plane logs](https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html)
- [Amazon EKS: Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [Amazon EKS: maximum pods per instance type](https://docs.aws.amazon.com/eks/latest/userguide/choosing-instance-type.html)
- [EKS best practices: identity and access management](https://docs.aws.amazon.com/eks/latest/best-practices/identity-and-access-management.html)
- [Amazon EKS pricing](https://aws.amazon.com/eks/pricing/)
