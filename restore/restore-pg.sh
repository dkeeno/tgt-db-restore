#!/usr/bin/env bash
# =============================================================================
# restore-pg.sh — pg_restore the cold-copy dump into tgt-rds-pg
# =============================================================================
#
# Invoked by restore-pg.tf via null_resource local-exec on a GitHub Actions
# ubuntu-latest runner. Idempotent — re-running with the same dump_sha256
# produces the same end state (because pg_restore --clean --if-exists drops
# objects first).
#
# Inputs (env vars set by Terraform):
#   REGION         AWS region (us-east-1)
#   BASTION_ID     EC2 instance ID of the tgt bastion (SSM jump host)
#   RDS_ENDPOINT   tgt-rds-pg DNS endpoint
#   RDS_DB         logical database name (enterprise_corp)
#   RDS_SECRET     Secrets Manager secret name with master credentials
#   LOCAL_PORT     local TCP port for the SSM port-forward
#   DUMP_PATH      absolute path to the .dump file

set -euo pipefail

log() { printf '\n\033[1;34m[restore-pg] %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m[restore-pg ERROR] %s\033[0m\n' "$*" >&2; exit 1; }

for v in REGION BASTION_ID RDS_ENDPOINT RDS_DB RDS_SECRET LOCAL_PORT DUMP_PATH; do
  [[ -n "${!v:-}" ]] || die "missing env var: $v"
done
[[ -f "$DUMP_PATH" ]] || die "dump file not found: $DUMP_PATH"

# ---------- Install missing tooling --------------------------------------
log "Installing required tools (pg client + session-manager-plugin) if missing"
if ! command -v pg_restore >/dev/null; then
  sudo apt-get update -qq
  # PostgreSQL APT repository for v16 client (Ubuntu repos lag)
  sudo apt-get install -y --no-install-recommends curl ca-certificates gnupg lsb-release
  sudo install -d /usr/share/postgresql-common/pgdg
  sudo curl -sS -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
    --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
  echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
    | sudo tee /etc/apt/sources.list.d/pgdg.list
  sudo apt-get update -qq
  sudo apt-get install -y --no-install-recommends postgresql-client-16
fi

if ! command -v session-manager-plugin >/dev/null; then
  curl -sS -L -o /tmp/ssm-plugin.deb \
    "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb"
  sudo dpkg -i /tmp/ssm-plugin.deb
fi

# ---------- Fetch master password ---------------------------------------
log "Fetching master password from Secrets Manager: $RDS_SECRET"
export PGPASSWORD=$(aws secretsmanager get-secret-value \
  --region "$REGION" --secret-id "$RDS_SECRET" \
  --query SecretString --output text | jq -r .password)
[[ -n "${PGPASSWORD:-}" ]] || die "could not retrieve PG password"

# ---------- Start SSM port-forward in the background --------------------
log "Starting SSM port-forward: local $LOCAL_PORT → $RDS_ENDPOINT:5432 via $BASTION_ID"
aws ssm start-session --region "$REGION" --target "$BASTION_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$RDS_ENDPOINT\"],\"portNumber\":[\"5432\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}" \
  > /tmp/ssm-pg.log 2>&1 &
SSM_PID=$!
trap "kill $SSM_PID 2>/dev/null || true" EXIT

# Wait for tunnel to come up
for i in {1..20}; do
  if (echo >/dev/tcp/localhost/$LOCAL_PORT) 2>/dev/null; then
    log "Tunnel ready after ${i}s"
    break
  fi
  sleep 1
done
(echo >/dev/tcp/localhost/$LOCAL_PORT) 2>/dev/null || die "tunnel did not come up in 20s"

# ---------- Run pg_restore ----------------------------------------------
log "Running pg_restore (--clean --if-exists for idempotency)"
PGSSLMODE=require pg_restore \
  -h localhost -p "$LOCAL_PORT" -U dbadmin -d "$RDS_DB" \
  --clean --if-exists --no-owner --no-acl --verbose \
  "$DUMP_PATH" 2>&1 | tail -40 || die "pg_restore failed"

# ---------- Verify --------------------------------------------------------
log "Verifying row counts in known tables"
PGSSLMODE=require psql -h localhost -p "$LOCAL_PORT" -U dbadmin -d "$RDS_DB" -At <<'SQL'
SELECT 'hr.employees=' || COUNT(*) FROM hr.employees;
SELECT 'hr.payroll=' || COUNT(*) FROM hr.payroll;
SELECT 'sales.orders=' || COUNT(*) FROM sales.orders;
SELECT 'finance.budgets=' || COUNT(*) FROM finance.budgets;
SELECT 'audit.change_log=' || COUNT(*) FROM audit.change_log;
SQL

log "PG restore complete"
