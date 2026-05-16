# =============================================================================
# outputs.tf
# =============================================================================

output "restored_targets" {
  description = "Summary of what was restored, by trigger hash."
  value = {
    pg_dump_sha256    = local.pg_dump_sha256
    pg_endpoint       = data.aws_db_instance.tgt_pg.endpoint
    pg_db_name        = var.rds_db_name
    docdb_dump_sha256 = local.docdb_dump_sha256
    docdb_endpoint    = data.aws_rds_cluster.tgt_docdb.endpoint
    docdb_db_name     = var.docdb_db_name
    bastion_used      = local.bastion_id
  }
}
