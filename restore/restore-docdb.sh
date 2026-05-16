#!/usr/bin/env bash
# =============================================================================
# restore-docdb.sh — mongorestore the cold-copy dump into tgt-docdb
# =============================================================================
#
# Invoked by restore-docdb.tf via null_resource local-exec.
# Idempotent — uses --drop to remove existing collections first.
#
# Inputs (env vars set by Terraform):
#   REGION          AWS region
#   BASTION_ID      EC2 instance ID of tgt bastion
#   DOCDB_ENDPOINT  DocumentDB cluster endpoint
#   DOCDB_DB        database name
#   DOCDB_SECRET    Secrets Manager secret name
#   LOCAL_PORT      local TCP port for SSM port-forward
#   DUMP_DIR        absolute path to the mongodump output directory
#   CA_BUNDLE       absolute path to the AWS RDS global CA bundle

set -euo pipefail

log() { printf '\n\033[1;34m[restore-docdb] %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m[restore-docdb ERROR] %s\033[0m\n' "$*" >&2; exit 1; }

for v in REGION BASTION_ID DOCDB_ENDPOINT DOCDB_DB DOCDB_SECRET LOCAL_PORT DUMP_DIR CA_BUNDLE; do
  [[ -n "${!v:-}" ]] || die "missing env var: $v"
done
[[ -d "$DUMP_DIR/$DOCDB_DB" ]] || die "dump dir not found: $DUMP_DIR/$DOCDB_DB"
[[ -f "$CA_BUNDLE" ]] || die "CA bundle not found: $CA_BUNDLE"

# ---------- Install missing tooling --------------------------------------
log "Installing required tools (mongodb-database-tools + session-manager-plugin) if missing"
if ! command -v mongorestore >/dev/null; then
  curl -sS -L -o /tmp/mongotools.deb \
    "https://fastdl.mongodb.org/tools/db/mongodb-database-tools-ubuntu2204-x86_64-100.16.1.deb"
  sudo dpkg -i /tmp/mongotools.deb || sudo apt-get install -fy
fi

if ! command -v session-manager-plugin >/dev/null; then
  curl -sS -L -o /tmp/ssm-plugin.deb \
    "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb"
  sudo dpkg -i /tmp/ssm-plugin.deb
fi

# ---------- Fetch master password ---------------------------------------
log "Fetching master password from Secrets Manager: $DOCDB_SECRET"
DOCDB_PASS=$(aws secretsmanager get-secret-value \
  --region "$REGION" --secret-id "$DOCDB_SECRET" \
  --query SecretString --output text | jq -r .password)
[[ -n "$DOCDB_PASS" ]] || die "could not retrieve DocDB password"

# ---------- Start SSM port-forward in background ------------------------
log "Starting SSM port-forward: local $LOCAL_PORT → $DOCDB_ENDPOINT:27017 via $BASTION_ID"
aws ssm start-session --region "$REGION" --target "$BASTION_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$DOCDB_ENDPOINT\"],\"portNumber\":[\"27017\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}" \
  > /tmp/ssm-docdb.log 2>&1 &
SSM_PID=$!
trap "kill $SSM_PID 2>/dev/null || true" EXIT

for i in {1..20}; do
  if (echo >/dev/tcp/localhost/$LOCAL_PORT) 2>/dev/null; then
    log "Tunnel ready after ${i}s"
    break
  fi
  sleep 1
done
(echo >/dev/tcp/localhost/$LOCAL_PORT) 2>/dev/null || die "tunnel did not come up in 20s"

# ---------- Run mongorestore --------------------------------------------
log "Running mongorestore (--drop for idempotent re-run)"
mongorestore \
  --host "localhost:${LOCAL_PORT}" \
  --username docdbadmin \
  --password "$DOCDB_PASS" \
  --authenticationDatabase admin \
  --ssl --sslCAFile="$CA_BUNDLE" --tlsInsecure \
  --drop \
  --db "$DOCDB_DB" \
  "$DUMP_DIR/$DOCDB_DB" 2>&1 | tail -20 || die "mongorestore failed"

# ---------- Verify --------------------------------------------------------
log "Verifying document counts per collection"
mongosh --quiet \
  "mongodb://docdbadmin:$(jq -rn --arg pw "$DOCDB_PASS" '$pw | @uri')@localhost:${LOCAL_PORT}/${DOCDB_DB}?tls=true&tlsCAFile=${CA_BUNDLE}&tlsAllowInvalidHostnames=true&authSource=admin&directConnection=true" \
  --eval 'db.getCollectionNames().forEach(c => print(c + "=" + db[c].countDocuments({})))' 2>&1 | tail -10

log "DocDB restore complete"
