# =============================================================================
# terraform.tfvars — concrete values for the tgt-db-restore stack
# =============================================================================

aws_region               = "us-east-1"
bastion_name_tag         = "tgt-bastion-01"
rds_db_identifier        = "tgt-rds-pg"
rds_db_name              = "enterprise_corp"
rds_secret_name          = "tgt-rds-pg-master-credentials"
docdb_cluster_identifier = "tgt-docdb"
docdb_db_name            = "enterprise_corp"
docdb_secret_name        = "tgt-docdb-master-credentials"
pg_local_port            = 15432
docdb_local_port         = 27018

# Bump these to force the null_resource to re-run even when dump hash is unchanged.
# Used to recover from the 2026-05-16 apply where pg_restore exit-1 (benign)
# was incorrectly treated as fatal by the shell script.
replay_pg    = "2026-05-16-retry-after-exitcode-fix"
replay_docdb = "2026-05-16-retry-after-exitcode-fix"
