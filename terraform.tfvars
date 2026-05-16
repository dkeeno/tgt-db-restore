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
