# Runbook: prove Pod Identity and IAM database login in dev

Use this to prove, in one paid session, that a pod reaches AWS and PostgreSQL
without any stored key or password, and that nothing else can. It applies to
the dev stack (`envs/dev`) after the `modules/pod-identity` change is merged.
It was first run for ZPP-37 on 2026-11-24 (results in the post-merge
verification on PR #24); later sessions reuse it.

Design decisions behind every step are in ADR-005 (IAM database
authentication) and the ZPP-37 decision record. Pass and fail criteria below
were set before the test and must not be changed during it.

## What is proved

| # | Claim | Pass when |
|---|---|---|
| P1 | A pod using the `inventory/inventory` service account gets the inventory role through Pod Identity | `sts get-caller-identity` in the pod shows the role `zen-pharma-dev-inventory-pod` |
| P2 | That pod logs in to PostgreSQL as `svc_inventory` with an IAM token over verified TLS | `psql` returns `svc_inventory` and `ssl = t` with `sslmode=verify-full` |
| N1 | A pod using any other service account gets no AWS credentials | The token step fails with no credentials found |
| N2 | The inventory pod cannot log in as the master user `pharma_admin` | Login refused |
| N3 | The inventory pod cannot log in as another IAM-enabled user `svc_other` | Login refused |
| L1 | The dev instance class has memory headroom for IAM authentication under the expected pool | 40 concurrent `svc_inventory` sessions held 10 minutes; all 40 succeed; zero failed `svc_inventory` logins; minimum FreeableMemory during the hold at or above the threshold written in the ticket after the baseline and before the load (see step 6) |
| C1 | Nothing is left running after the session | Destroy completes and every leftover check is empty |

N3 matters more than N2: `svc_other` has the `rds_iam` role, so the only thing
stopping the login is the IAM policy on the inventory role. N2 is refused for
two reasons (no `rds_iam` role and no IAM permission).

## Safety rules for the session

- Fake data only. No customer data, no real email addresses.
- The master password is read into a shell variable and passed on stdin. It is
  never printed, never put in a pod spec, environment variable, argument or file.
- Evidence files are saved with `tee` and masked before they leave the laptop:
  `sed -E 's/[0-9]{12}/<ACCOUNT_ID>/g'`.
- **Stop rule:** if a step fails and is not understood within 15 minutes, or the
  session passes 2 h 30 min, save what you have, go to step 9 (destroy) and open
  a ticket. Never leave the stack running to debug later.

## Before the session (free, during the week)

Do these on the laptop; none of them costs money.

1. **Review this runbook** and write questions in ZPP-37.
2. **Check your public IP** still matches the `EKS_PUBLIC_ACCESS_CIDRS` repository
   secret (the EKS endpoint only accepts that /32, ADR-004). If it changed,
   update the secret before the session, or kubectl will time out.
3. **Tools:** `aws --version` (CLI v2), `kubectl version --client`, `terraform version`,
   `jq --version`. Log in: `aws sso login --profile zpp-admin`.
4. **Download the RDS CA bundle** (public file, used for `sslmode=verify-full`):

   ```bash
   mkdir -p ~/zpp-proof && cd ~/zpp-proof
   curl -fsSLo global-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
   grep -c 'BEGIN CERTIFICATE' global-bundle.pem   # more than 0
   ```

5. **Pin the two test images by digest** (ADR-006: tag plus digest). Pick the
   current tags, then record the digests:

   ```bash
   docker buildx imagetools inspect public.ecr.aws/aws-cli/aws-cli:<2.x.y> | grep -m1 Digest
   docker buildx imagetools inspect public.ecr.aws/docker/library/postgres:18-alpine | grep -m1 Digest
   ```

   Pod Identity needs AWS CLI v2 version 2.15.0 or later, so any current 2.x tag
   works. Write both `image:tag@sha256:...` values into `~/zpp-proof/images.env`:

   ```bash
   cat > ~/zpp-proof/images.env <<'EOF'
   AWSCLI_IMAGE=public.ecr.aws/aws-cli/aws-cli:<tag>@sha256:<digest>
   PG_IMAGE=public.ecr.aws/docker/library/postgres:18-alpine@sha256:<digest>
   EOF
   ```

6. **Budget:** check the `zpp-monthly` budget has room for about 3 hours of EKS
   and RDS (ADR-004 and ADR-005 cost tables).
7. **kubectl version:** the client must be within one minor version of the
   cluster (`kubernetes_version` in `envs/dev`). Compare `kubectl version --client`;
   if it is older, install the matching minor from the official release with its
   checksum before the session:

   ```bash
   V=$(curl -fsSL https://dl.k8s.io/release/stable-1.37.txt)   # cluster minor
   curl -fsSLO "https://dl.k8s.io/release/$V/bin/linux/amd64/kubectl"
   curl -fsSLO "https://dl.k8s.io/release/$V/bin/linux/amd64/kubectl.sha256"
   echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check    # must print OK
   sudo install -m 0755 kubectl "$(command -v kubectl)"
   ```

8. **PR up to date and plan re-read (morning of the session):** branch
   protection only merges a PR that contains the latest `main`. Check it, and if
   it is behind, rebase it (no unsigned merge commit for the DCO check), wait
   for the checks and read the new plan:

   ```bash
   gh pr view <n> --json mergeStateStatus,mergeable --jq '"\(.mergeStateStatus) \(.mergeable)"'   # CLEAN MERGEABLE
   gh pr update-branch <n> --rebase && gh pr checks <n> --watch
   gh pr view <n> --json comments --jq '.comments[-1].body' | grep -m1 '^Plan:'
   ```

   If there is no PR to merge (the change is already on `main` and its
   deployment was rejected at the gate), re-run that `terraform-deploy` run
   instead (`gh run rerun <run id>`) and approve it in step 1. Re-runs are only
   possible for 30 days after the original run.

## Session timeline (about 2 hours)

| Step | What | Time box |
|---|---|---|
| 1 | Merge PR #24, approve the dev apply | 35 min (mostly waiting) |
| 2 | Connect and check the association | 5 min |
| 3 | Create database users (admin pod) | 10 min |
| 4 | P1 + P2: positive login | 10 min |
| 5 | N1, N2, N3: negative tests | 15 min |
| 6 | L1: baseline, 40 sessions for 10 minutes, memory and failed logins | 25 min |
| 7 | Clean up test objects | 5 min |
| 8 | Save and mask evidence | 5 min |
| 9 | Destroy and leftover checks | 25 min |

Each step saves its own output with `tee` into `~/zpp-proof/`. Do not record
the whole terminal: the admin step must never be captured.

## 1. Merge and apply

```bash
cd ~/code/DevSecOps-Project/zen-infra
gh pr checks <n> && gh pr merge <n> --squash --delete-branch
git switch main && git pull --ff-only
```

If the merge call fails with an API error (for example HTTP 503), check the
state before retrying: `gh pr view <n> --json state`. Retry only if it is still
`OPEN`. Never use `--admin`: it bypasses branch protection.

Approve the `dev` deployment in GitHub Actions when the plan shows
**58 to add, 0 to change, 0 to destroy**. Any other number: stop and read the
plan before approving. The hard stop (2 h 30 min) counts from the merge.

## 2. Connect and check the association

```bash
cd ~/code/DevSecOps-Project/zen-infra/envs/dev
export AWS_PROFILE=zpp-admin AWS_REGION=us-east-1
CLUSTER=$(terraform output -raw eks_cluster_name)
PGHOST=$(terraform output -raw rds_endpoint | cut -d: -f1)
SECRET_ARN=$(terraform output -raw rds_master_user_secret_arn)
aws eks update-kubeconfig --name "$CLUSTER"
kubectl get nodes
aws eks list-pod-identity-associations --cluster-name "$CLUSTER" \
  | tee ~/zpp-proof/02-associations.json
```

Expected: nodes `Ready`; one association for namespace `inventory`, service
account `inventory`.

Create the namespaces, service accounts and CA config map:

```bash
kubectl create namespace inventory
kubectl create namespace dbadmin
kubectl -n inventory create serviceaccount inventory
kubectl -n inventory create serviceaccount other
kubectl -n inventory create configmap rds-ca --from-file=$HOME/zpp-proof/global-bundle.pem
kubectl -n dbadmin create configmap rds-ca --from-file=$HOME/zpp-proof/global-bundle.pem
source ~/zpp-proof/images.env
```

## 3. Create the database users

The admin pod runs `psql` only. The password reaches it on stdin.

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata: {name: dbadmin, namespace: dbadmin}
spec:
  restartPolicy: Never
  automountServiceAccountToken: false
  securityContext: {runAsNonRoot: true, runAsUser: 70, runAsGroup: 70, seccompProfile: {type: RuntimeDefault}}
  containers:
  - name: psql
    image: ${PG_IMAGE}
    command: ["sleep", "3600"]
    securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}
    volumeMounts: [{name: ca, mountPath: /certs, readOnly: true}]
  volumes: [{name: ca, configMap: {name: rds-ca}}]
EOF
kubectl -n dbadmin wait --for=condition=Ready pod/dbadmin --timeout=180s
```

Run SQL as the master user. The password is read into a variable and piped in:

```bash
admin_sql() {
  local pw
  pw=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" \
        --query SecretString --output text | jq -r .password)
  printf '%s\n' "$pw" | kubectl -n dbadmin exec -i dbadmin -- sh -c \
    'read -r PGPASSWORD; export PGPASSWORD; psql "host='"$PGHOST"' port=5432 dbname=pharmadb user=pharma_admin sslmode=verify-full sslrootcert=/certs/global-bundle.pem" -v ON_ERROR_STOP=1 -Atc "$1"' sh "$1"
  unset pw
}

admin_sql "CREATE USER svc_inventory; GRANT rds_iam TO svc_inventory;
           CREATE USER svc_other;     GRANT rds_iam TO svc_other;
           REVOKE CONNECT ON DATABASE pharmadb FROM PUBLIC;
           GRANT CONNECT ON DATABASE pharmadb TO svc_inventory, svc_other;" \
  | tee ~/zpp-proof/03-create-users.txt

admin_sql "SELECT r.rolname, pg_has_role(r.rolname, 'rds_iam', 'member')
           FROM pg_roles r WHERE r.rolname IN ('svc_inventory','svc_other','pharma_admin')
           ORDER BY 1;" | tee ~/zpp-proof/03-roles.txt
```

Expected in `03-roles.txt`: `pharma_admin|f`, `svc_inventory|t`, `svc_other|t`.
The master user must never be a member of `rds_iam`.

## 4. Positive test (P1, P2)

One probe pod definition is used for every test. It has two containers: the
first gets an IAM token with the AWS CLI, the second logs in with `psql`.

```bash
probe() {  # probe <name> <service-account> <db-user> <mode: login|load>
  kubectl -n inventory delete pod "$1" --ignore-not-found --wait=true >/dev/null
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata: {name: $1, namespace: inventory}
spec:
  serviceAccountName: $2
  restartPolicy: Never
  securityContext: {runAsNonRoot: true, runAsUser: 1000, runAsGroup: 1000, seccompProfile: {type: RuntimeDefault}}
  volumes:
  - {name: shared, emptyDir: {medium: Memory}}
  - {name: home, emptyDir: {}}
  - {name: ca, configMap: {name: rds-ca}}
  initContainers:
  - name: token
    image: ${AWSCLI_IMAGE}
    env: [{name: HOME, value: /home/probe}, {name: AWS_REGION, value: ${AWS_REGION}}, {name: PGHOST, value: ${PGHOST}}, {name: PGUSER, value: $3}]
    command: ["sh", "-c", "aws sts get-caller-identity --query Arn --output text > /shared/caller && aws rds generate-db-auth-token --hostname \$PGHOST --port 5432 --region \$AWS_REGION --username \$PGUSER > /shared/token"]
    securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}
    volumeMounts: [{name: shared, mountPath: /shared}, {name: home, mountPath: /home/probe}]
  containers:
  - name: psql
    image: ${PG_IMAGE}
    env: [{name: PGHOST, value: ${PGHOST}}, {name: PGUSER, value: $3}, {name: MODE, value: $4}]
    command: ["sh", "-c"]
    args:
    - |
      echo "caller: \$(cat /shared/caller)"
      export PGPASSWORD="\$(cat /shared/token)"
      CONN="host=\$PGHOST port=5432 dbname=pharmadb user=\$PGUSER sslmode=verify-full sslrootcert=/certs/global-bundle.pem"
      if [ "\$MODE" = login ]; then
        psql "\$CONN" -v ON_ERROR_STOP=1 -Atc "SELECT current_user, ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()"
      else
        pids=""
        for i in \$(seq 1 40); do
          psql "\$CONN application_name=load\$i" -Atc "SELECT pg_sleep(600)" >/dev/null 2>/tmp/err\$i &
          pids="\$pids \$!"
        done
        ok=0; fail=0
        for p in \$pids; do if wait \$p; then ok=\$((ok+1)); else fail=\$((fail+1)); fi; done
        echo "sessions ok=\$ok failed=\$fail"; cat /tmp/err* 2>/dev/null | sort | uniq -c
      fi
    securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}
    volumeMounts: [{name: shared, mountPath: /shared, readOnly: true}, {name: ca, mountPath: /certs, readOnly: true}]
EOF
}

probe p1-inventory inventory svc_inventory login
kubectl -n inventory wait --for=jsonpath='{.status.phase}'=Succeeded pod/p1-inventory --timeout=180s
kubectl -n inventory logs p1-inventory -c psql | tee ~/zpp-proof/04-positive.txt
```

Expected in `04-positive.txt`:

- `caller:` an `assumed-role/zen-pharma-dev-inventory-pod/...` ARN (P1)
- `svc_inventory|t` (P2: right user, TLS on, certificate verified by `verify-full`)

## 5. Negative tests (N1, N2, N3)

```bash
# N1: other service account, no Pod Identity association
probe n1-other-sa other svc_inventory login
sleep 60; kubectl -n inventory get pod n1-other-sa | tee ~/zpp-proof/05-n1.txt
kubectl -n inventory logs n1-other-sa -c token 2>&1 | tee -a ~/zpp-proof/05-n1.txt

# N2: inventory role, master user
probe n2-master inventory pharma_admin login
sleep 60; kubectl -n inventory logs n2-master -c psql 2>&1 | tee ~/zpp-proof/05-n2.txt

# N3: inventory role, another IAM-enabled user
probe n3-other-user inventory svc_other login
sleep 60; kubectl -n inventory logs n3-other-user -c psql 2>&1 | tee ~/zpp-proof/05-n3.txt
```

Expected:

- N1: pod stuck in `Init:Error`; token log says no credentials were found. The
  node's own role is out of reach too, because pods cannot reach the instance
  metadata service (hop limit 1, ADR-004).
- N2 and N3: `caller` is still the inventory role (signing a token always works
  locally), but PostgreSQL refuses the login (`PAM authentication failed` or
  `password authentication failed` for the user). The refusal is the proof.

## 6. Memory headroom (L1)

Thresholds come from a measured baseline (Sprint 4 retro action E3). Record
the start of the baseline and wait 5 minutes with no load. Read the baseline,
then write the pass threshold in the ticket **before** starting the load, with
its source (the baseline minimum, and the 300 to 1,000 MiB AWS gives for IAM
database authentication in ADR-005). The 256 MiB used for db.t4g.micro in
ZPP-37 failed against a baseline of about 102 MiB, which led to db.t4g.small.

```bash
BASE_START=$(date -u +%Y-%m-%dT%H:%M:%SZ); sleep 300
LOAD_START=$(date -u +%Y-%m-%dT%H:%M:%SZ); LOAD_START_MS=$(($(date +%s)*1000))
# (mem is defined below; run it now for the baseline, write the threshold in the ticket, then continue)
probe l1-load inventory svc_inventory load
sleep 120
admin_sql "SELECT count(*) FROM pg_stat_activity WHERE usename = 'svc_inventory';" \
  | tee ~/zpp-proof/06-active-sessions.txt          # expect 40
kubectl -n inventory wait --for=jsonpath='{.status.phase}'=Succeeded pod/l1-load --timeout=720s
LOAD_END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
kubectl -n inventory logs l1-load -c psql | tee ~/zpp-proof/06-load-result.txt   # expect ok=40 failed=0
```

Read the metrics (standard RDS metrics, 60-second points):

```bash
DB_ID=zen-pharma-dev-postgres
mem() { aws cloudwatch get-metric-statistics --namespace AWS/RDS --metric-name FreeableMemory \
  --dimensions Name=DBInstanceIdentifier,Value=$DB_ID --start-time "$1" --end-time "$2" \
  --period 60 --statistics Minimum --query 'sort_by(Datapoints,&Timestamp)[].[Timestamp,Minimum]' --output text; }
mem "$BASE_START" "$LOAD_START" | tee ~/zpp-proof/06-mem-baseline.txt
mem "$LOAD_START" "$LOAD_END"   | tee ~/zpp-proof/06-mem-load.txt
sort -k2 -n ~/zpp-proof/06-mem-load.txt | head -1    # minimum during the hold

aws logs filter-log-events --log-group-name "/aws/rds/instance/$DB_ID/postgresql" \
  --start-time "$LOAD_START_MS" --filter-pattern '"authentication failed"' \
  --query 'events[].message' --output text | tee ~/zpp-proof/06-failed-logins.txt
```

Pass: `06-active-sessions.txt` shows 40; `06-load-result.txt` shows `ok=40 failed=0`;
the minimum in `06-mem-load.txt` is at or above the threshold written in the
ticket before the load; `06-failed-logins.txt` has no line for `svc_inventory`.

Record the baseline minimum next to the load minimum. The difference is the
cost of 40 sessions. It does not isolate IAM authentication's own overhead,
which would need Enhanced Monitoring (off in dev).

If L1 fails: it is a result, not an error. Record it; the fallback in ADR-005
is db.t4g.small, decided in a follow-up ticket.

## 7. Clean up test objects

```bash
admin_sql "REVOKE CONNECT ON DATABASE pharmadb FROM svc_other; DROP USER svc_other;"
kubectl delete namespace inventory dbadmin
```

`svc_inventory` and everything else go with the destroy.

## 8. Save and mask evidence

```bash
cd ~/zpp-proof
for f in 0*.txt 0*.json; do
  sed -E -e 's/[0-9]{12}/<ACCOUNT_ID>/g' \
         -e 's/[a-z0-9-]+\.[a-z0-9]+\.us-east-1\.rds\.amazonaws\.com/<RDS_HOST>/g' \
         -e 's/10\.[0-9]+\.[0-9]+\.[0-9]+/<PRIVATE_IP>/g' "$f" > "masked-$f"; done
grep -lE '[0-9]{12}|rds\.amazonaws\.com' masked-* && echo "UNMASKED VALUE FOUND"
```

Only `masked-*` files are pasted into Jira or GitHub. The last command must
print nothing.

## 9. Destroy and leftover checks

```bash
cd ~/code/DevSecOps-Project/zen-infra/envs/dev
terraform init -backend-config=backend.hcl
terraform destroy          # expect 58 to destroy; type yes only if it matches
aws eks list-clusters --query 'clusters' --output text
aws rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier' --output text
aws iam get-role --role-name zen-pharma-dev-inventory-pod 2>&1 | grep -c NoSuchEntity   # 1
aws secretsmanager list-secrets --query "SecretList[?starts_with(Name,'rds!')].Name" --output text
aws ec2 describe-nat-gateways --filter Name=state,Values=available --query 'NatGateways[].NatGatewayId' --output text
aws ec2 describe-addresses --query 'Addresses[].AllocationId' --output text
```

All lists must be empty (secrets scheduled for deletion count as gone).

## After the session

- ZPP-37 evidence comment: the table of P1 to C1 with pass or fail and the masked
  files.
- Post-merge verification comment on zen-infra PR #24 (Definition of Done).
- Update ADR-005 verification section (memory headroom result), the Build
  Guide, the Story Bank and the project-lotus status line.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| kubectl times out | Your IP is not in the EKS endpoint allow-list | Update the `EKS_PUBLIC_ACCESS_CIDRS` secret and re-run the apply |
| P1 pod `Init:Error`, no credentials | Pod started before the association existed, or wrong service account | Check step 2 output; delete and re-create the probe pod |
| `ImagePullBackOff` | Wrong digest or no egress from nodes | Re-check `images.env`; confirm the NAT gateway exists |
| `psql: ... certificate verify failed` | CA bundle missing or wrong host name | Re-create the `rds-ca` config map; use the endpoint host, not an IP |
| P2 `PAM authentication failed` for `svc_inventory` | `rds_iam` not granted, name case differs, or token older than 15 minutes | Re-check `03-roles.txt`; re-run the probe for a fresh token |
| Fewer than 40 sessions | Connection limit or a slow token step | Read `06-load-result.txt` error counts; do not raise limits during the test |
| `gh pr merge`: head branch is not up to date | Branch protection requires the latest `main` in the PR | `gh pr update-branch <n> --rebase`, wait for checks, re-read the plan, then merge (pre-flight step 8) |
| HTTP 503 from api.github.com on merge | GitHub-side error; the merge may or may not have happened | `gh pr view <n> --json state`; retry only if `OPEN`; check githubstatus.com |
| kubectl behaves oddly or warns about versions | Client more than one minor version from the cluster | Pre-flight step 7: install the matching minor with its checksum |
| A rejected deployment shows the apply jobs as `failure` | GitHub reports a job rejected at an environment gate as failed | Confirm with `gh api repos/<owner>/<repo>/actions/runs/<id>/approvals` (`rejected`) and that no steps ran |

## References

- [Amazon RDS: creating a database account for IAM authentication](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.DBAccounts.html)
- [Amazon RDS: connecting with IAM authentication from the AWS CLI and psql](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.Connecting.AWSCLI.PostgreSQL.html)
- [Amazon RDS: SSL/TLS certificate bundles](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html)
- [Amazon EKS: how Pod Identity works](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-how-it-works.html)
- [Amazon EKS: minimum SDK and CLI versions for Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-minimum-sdk.html)
- [Amazon RDS: CloudWatch metrics (FreeableMemory)](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-metrics.html)
- [AWS CLI: cloudwatch get-metric-statistics](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/cloudwatch/get-metric-statistics.html)
- [AWS CLI: logs filter-log-events](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/logs/filter-log-events.html)
- [Kubernetes: configure a security context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [PostgreSQL: psql](https://www.postgresql.org/docs/18/app-psql.html)
- ADR-004 (EKS design), ADR-005 (RDS design), ADR-006 (image pinning)
