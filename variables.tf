# =============================================================================
# variables.tf
# =============================================================================

variable "aws_region" {
  description = "AWS region for all data lookups."
  type        = string
  default     = "us-east-1"
}

variable "bastion_name_tag" {
  description = "Name tag of the running bastion EC2 used as the SSM jump host."
  type        = string
  default     = "tgt-bastion-01"
}

variable "rds_db_identifier" {
  description = "RDS PostgreSQL DB instance identifier."
  type        = string
  default     = "tgt-rds-pg"
}

variable "rds_db_name" {
  description = "PostgreSQL logical database name to restore into."
  type        = string
  default     = "enterprise_corp"
}

variable "rds_secret_name" {
  description = "Secrets Manager secret holding the RDS master credentials."
  type        = string
  default     = "tgt-rds-pg-master-credentials"
}

variable "docdb_cluster_identifier" {
  description = "DocumentDB cluster identifier."
  type        = string
  default     = "tgt-docdb"
}

variable "docdb_db_name" {
  description = "DocumentDB database name to restore into."
  type        = string
  default     = "enterprise_corp"
}

variable "docdb_secret_name" {
  description = "Secrets Manager secret holding the DocumentDB master credentials."
  type        = string
  default     = "tgt-docdb-master-credentials"
}

variable "pg_local_port" {
  description = "Local port for the SSM port-forward to RDS."
  type        = number
  default     = 15432
}

variable "docdb_local_port" {
  description = "Local port for the SSM port-forward to DocumentDB."
  type        = number
  default     = 27018
}
