# tgt-db-restore

Cold-copy restore of the Phase 1 dumps into the new `tgt` databases.

## What this stack does

| Resource | Action |
|---|---|
| `null_resource.restore_pg` | `pg_restore --clean --if-exists` the committed `restore/postgres-enterprise_corp.dump` into `tgt-rds-pg.enterprise_corp` |
| `null_resource.restore_docdb` | `mongorestore --drop` the committed `restore/docdb-enterprise_corp/` into `tgt-docdb.enterprise_corp` |

Both are idempotent — re-running with the same dump produces the same end state.

## How it works

1. Data sources look up the running bastion (Name tag `tgt-bastion-01`), the RDS endpoint, and the DocDB endpoint.
2. The shell scripts (`restore/restore-pg.sh`, `restore/restore-docdb.sh`) are invoked via `local-exec` on the GH Actions runner. They:
   - Install `postgresql-client-16`, `mongodb-database-tools`, and `session-manager-plugin` on the runner if missing.
   - Fetch the master password from Secrets Manager.
   - Open an SSM port-forward through the bastion to the DB endpoint (background process).
   - Run `pg_restore` / `mongorestore` against `localhost:<forwarded port>`.
   - Verify counts.
   - Tear down the port-forward.

The restore is triggered when:
- The dump file's SHA256 changes (you commit a new dump).
- The target DB endpoint changes (e.g. cluster recreated).
- The bastion instance ID changes.
- The `replay_pg` or `replay_docdb` variable changes (manual re-run trigger).

## Apply pattern

Standard sbx-cluster-iac pattern: validate → plan → apply (gated on `production` environment).

The committed dump files are taken from the Phase 1 bundle (`Alpha/cold-copy/`) and re-used directly. Total committed size: ~400 KB.

## Required permissions on the runner

- `secretsmanager:GetSecretValue` on `tgt-rds-pg-master-credentials` and `tgt-docdb-master-credentials`
- `ssm:StartSession` on the bastion instance
- `rds:DescribeDBInstances` and `docdb:DescribeDBClusters` for the data-source lookups
- `ec2:DescribeInstances` for bastion discovery

All covered by `tgt-github-actions` role's `AdministratorAccess` (sandbox-grade).

## Restore verification

After apply, check the `restored_targets` output for the SHA256 hashes and DB endpoints, and inspect the workflow logs for the row/document counts printed by the restore scripts.
