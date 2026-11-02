# Runbook: Terraform state lock recovery

Use this when a Terraform command fails with "Error acquiring the state lock",
or when state needs to be restored to an earlier version.
Applies to every stack whose state lives in the S3 state bucket
(bootstrap, envs/dev, envs/qa, envs/prod). Run commands from the stack folder.

## Background

- State is stored in S3 at `<stack>/terraform.tfstate`, encrypted with the
  state KMS key, with versioning on.
- Locking uses S3 native locking (`use_lockfile = true`). While a command runs,
  Terraform holds `<stack>/terraform.tfstate.tflock`. A second command that tries
  to create it gets `412 PreconditionFailed`, and that refusal is the lock.

## Symptoms

```
Error: Error acquiring the state lock
api error PreconditionFailed: At least one of the pre-conditions you specified did not hold
Lock Info:
  ID:        <LOCK_ID>
  Path:      <bucket>/<stack>/terraform.tfstate
  Operation: OperationTypeApply
  Who:       user@host
  Created:   <timestamp UTC>
```

| Field | Use it to |
| --- | --- |
| ID | Pass to `terraform force-unlock`. Not the same as an S3 VersionId |
| Who | Find and ask the person or host holding the lock |
| Operation | See what was running (plan, apply) |
| Created | Judge age (UTC). Age alone does not prove a lock is stale |
| Path | Confirm it is the stack you expect |

A lock is normal while someone is working, including an apply waiting at
`Enter a value:`. It is only "stuck" if its owner is gone.

## 1. Check before unlocking

```
STACK=envs/dev                                   # the stack you are working on
B=$(grep bucket backend.hcl | cut -d'"' -f2)
test -n "$B" || echo "Bucket not found: run from the stack folder"
```

1. Is a Terraform run active on this machine?
   ```
   ps -eo pid,etime,args | grep -E "[t]erraform (apply|plan|destroy|import)" || echo "no run active"
   ```
   `terraform-ls` (the editor language server) does not touch state; ignore it.
2. Is a CI run active or queued for this repo?
   ```
   gh run list --limit 5
   ```
3. Ask the person in `Who`. If they are mid-apply, wait.
4. Confirm the lock file exists:
   ```
   aws s3 ls "s3://$B/$STACK/"
   ```

## 2. When NOT to unlock

- An apply, destroy or import is still running anywhere (local or CI),
  including one waiting for confirmation.
- The lock is recent and you cannot reach its owner. Wait, and escalate.
- You are not sure which stack or account the lock belongs to.
- AWS errors (access denied, network) stop you checking the lock reliably.
- You plan to use `-lock=false` instead. Never do this on shared state.

Unlocking under a live run lets two writers change state at once and can corrupt it.

## 3. Unlock and verify

```
terraform force-unlock <LOCK_ID>                                    # answer yes
aws s3api head-object --bucket "$B" --key "$STACK/terraform.tfstate.tflock"   # want 404 Not Found
terraform plan -no-color | grep -E "^Plan:|No changes"
```

A `404` proves the lock is gone; a `403` proves nothing. The plan shows Terraform
can take and release the lock again. Record the lock ID, owner, age and why it was
safe to unlock in the incident ticket.

## 4. Restore an earlier state version

Use only when the current state is wrong (corrupted or written by a mistaken
command), never to "undo" real infrastructure changes. Restoring state does not
recreate deleted AWS resources.

1. Freeze the stack: tell the team; complete section 1; pause CI.
2. Back up the current state to a private folder outside the repo:
   ```
   umask 077
   R=$(mktemp -d /tmp/state-recovery.XXXXXX)
   terraform state pull > "$R/current.tfstate"
   ```
3. List state versions only:
   ```
   aws s3api list-object-versions --bucket "$B" --prefix "$STACK/terraform.tfstate" \
     --query "Versions[?Key=='$STACK/terraform.tfstate'].[LastModified,VersionId,Size,IsLatest]" \
     --output table | cat
   ```
4. Download and inspect the candidate:
   ```
   aws s3api get-object --bucket "$B" --key "$STACK/terraform.tfstate" \
     --version-id <VERSION_ID> "$R/candidate.tfstate" >/dev/null
   jq '{serial, lineage, resources: ([.resources[]? | select(.mode=="managed")] | length)}' "$R/candidate.tfstate"
   jq '{serial, lineage}' "$R/current.tfstate"
   ```
   **The lineage must match.** A different lineage is a different state: stop.
5. Restore through Terraform, which takes the lock (never overwrite the S3 object directly):
   ```
   terraform state push "$R/candidate.tfstate"
   ```
   Terraform rejects an older serial. Only for a reviewed rollback of a confirmed
   bad write, with matching lineage and all writers paused, use
   `terraform state push -force "$R/candidate.tfstate"`. Never use `-force` to get
   past a lineage mismatch.
6. Verify, then review every difference before any apply:
   ```
   terraform state list
   terraform plan -no-color
   ```
   Use `terraform apply -refresh-only` if state must be updated from real infrastructure.
   Delete `$R` once the incident is closed.

## 5. Deleting the state bucket (whole-project teardown only)

1. Destroy every stack that stores state in the bucket.
2. Move the bootstrap state back to local: remove its backend block,
   `terraform init -migrate-state`.
3. Reviewed PR: remove `prevent_destroy`, set `force_destroy = true`; apply.
   `force_destroy` makes Terraform delete every object version and lock version.
4. `terraform destroy` the bootstrap stack.

`aws s3 rm --recursive` does not remove old versions from a versioned bucket,
so do not use it to empty this bucket.

## Tips

- Use `-no-color` whenever you grep Terraform output; colour codes break patterns.
- Shell variables like `B` and `STACK` exist only in the terminal that set them.
- Lock ID, S3 VersionId, serial and lineage are different things; do not mix them up.
- Keep state files out of Git, tickets and logs: they can contain secrets.
- Old `.tflock` versions build up in the versioned bucket; the bucket's lifecycle
  rule expires old versions after 90 days.

## Why not delete the lock file?

A reference project ran `aws s3 rm ... .tflock` after every failed pipeline job.
That frees the lock even when another run is still writing state, which can
corrupt it. `force-unlock` after the checks above is the safe path.
