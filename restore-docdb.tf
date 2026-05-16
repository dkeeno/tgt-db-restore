# =============================================================================
# restore-docdb.tf — DocumentDB cold-copy restore
# =============================================================================
#
# Restores Alpha/cold-copy/docdb-enterprise_corp/ (committed at
# restore/docdb-enterprise_corp/) into the new tgt-docdb cluster.
#
# Mechanics:
#   1. Look up the DocumentDB endpoint.
#   2. null_resource.restore_docdb runs restore/restore-docdb.sh which:
#      - Installs mongodb-database-tools + session-manager-plugin if missing.
#      - Fetches master password from Secrets Manager.
#      - Starts SSM port-forward (local 27018 → DocDB:27017) in background.
#      - Runs mongorestore --drop (idempotent re-run) with TLS + CA bundle.
#      - Tears down port-forward.
#
# Triggers re-run if:
#   - any committed BSON metadata or data file changes
#   - DocDB endpoint changes
#   - manual replay variable changes

data "aws_docdb_cluster" "tgt_docdb" {
  cluster_identifier = var.docdb_cluster_identifier
}

# Hash all files in the dump directory so any content change re-triggers restore
locals {
  docdb_dump_dir   = "${path.module}/restore/docdb-enterprise_corp"
  docdb_dump_files = fileset(local.docdb_dump_dir, "**/*")
  docdb_dump_sha256 = sha256(join("", [
    for f in sort(local.docdb_dump_files) :
    filesha256("${local.docdb_dump_dir}/${f}")
  ]))
  docdb_ca_bundle_path = "${path.module}/restore/global-bundle.pem"
}

variable "replay_docdb" {
  description = "Set to any new value to force re-run of the docdb restore step."
  type        = string
  default     = ""
}

resource "null_resource" "restore_docdb" {
  triggers = {
    dump_sha256    = local.docdb_dump_sha256
    docdb_endpoint = data.aws_docdb_cluster.tgt_docdb.endpoint
    bastion_id     = local.bastion_id
    replay         = var.replay_docdb
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      export REGION="${var.aws_region}"
      export BASTION_ID="${local.bastion_id}"
      export DOCDB_ENDPOINT="${data.aws_docdb_cluster.tgt_docdb.endpoint}"
      export DOCDB_DB="${var.docdb_db_name}"
      export DOCDB_SECRET="${var.docdb_secret_name}"
      export LOCAL_PORT="${var.docdb_local_port}"
      export DUMP_DIR="${local.docdb_dump_dir}"
      export CA_BUNDLE="${local.docdb_ca_bundle_path}"
      bash "${path.module}/restore/restore-docdb.sh"
    EOT
  }
}
