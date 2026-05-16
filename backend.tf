# =============================================================================
# backend.tf — shared S3 backend, unique state key
# =============================================================================

terraform {
  backend "s3" {
    bucket         = "sbx-tfstate-784916389752-us-east-1"
    key            = "tgt-iac/tgt-db-restore.tfstate"
    region         = "us-east-1"
    dynamodb_table = "sbx-tfstate-locks"
    encrypt        = true
  }
}
