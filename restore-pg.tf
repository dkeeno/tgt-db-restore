# =============================================================================
# restore-pg.tf — PostgreSQL cold-copy restore
# =============================================================================
#
# Restores Alpha/cold-copy/postgres-enterprise_corp.dump (committed at
# restore/postgres-enterprise_corp.dump) into the new tgt-rds-pg instance.
#
# Mechanics:
#   1. Look up the running bastion EC2 by Name tag.
#   2. Look up the new RDS endpoint.
#   3. null_resource.restore_pg runs restore/restore-pg.sh which:
#      - Installs postgresql-client-16 + session-manager-plugin on the
#        GH Actions runner (if missing).
#      - Fetches the master password from Secrets Manager.
#      - Starts an SSM port-forward (local 15432 → RDS:5432) in background.
#      - Runs pg_restore --clean --if-exists (idempotent re-run).
#      - Verifies row counts in 4 known tables vs Alpha-captured baseline.
#      - Tears down the port-forward.
#
# Triggers:
#   - dump_sha256: hash of the committed dump file. Changes re-run restore.
#   - rds_endpoint: re-run if RDS endpoint changes (e.g. cluster recreate).
#   - replay: optional manual trigger via -var='replay_pg=<anything>' to
#     force a re-run without changing the dump.

# -----------------------------------------------------------------------------
# Data sources — discover the live target environment
# -----------------------------------------------------------------------------
data "aws_instances" "bastion" {
  instance_tags = {
    Name = var.bastion_name_tag
  }
  instance_state_names = ["running"]
}

data "aws_db_instance" "tgt_pg" {
  db_instance_identifier = var.rds_db_identifier
}

# -----------------------------------------------------------------------------
# Hash of the committed dump — drives idempotent re-runs
# -----------------------------------------------------------------------------
locals {
  pg_dump_path   = "${path.module}/restore/postgres-enterprise_corp.dump"
  pg_dump_sha256 = filesha256(local.pg_dump_path)
  bastion_id     = data.aws_instances.bastion.ids[0]
}

# -----------------------------------------------------------------------------
# Optional manual replay trigger
# -----------------------------------------------------------------------------
variable "replay_pg" {
  description = "Set to any new value to force re-run of the pg restore step."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# The restore action
# -----------------------------------------------------------------------------
resource "null_resource" "restore_pg" {
  triggers = {
    dump_sha256  = local.pg_dump_sha256
    rds_endpoint = data.aws_db_instance.tgt_pg.endpoint
    bastion_id   = local.bastion_id
    replay       = var.replay_pg
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      export REGION="${var.aws_region}"
      export BASTION_ID="${local.bastion_id}"
      export RDS_ENDPOINT="${data.aws_db_instance.tgt_pg.address}"
      export RDS_DB="${var.rds_db_name}"
      export RDS_SECRET="${var.rds_secret_name}"
      export LOCAL_PORT="${var.pg_local_port}"
      export DUMP_PATH="${local.pg_dump_path}"
      bash "${path.module}/restore/restore-pg.sh"
    EOT
  }
}
