# =============================================================================
# providers.tf
# =============================================================================

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project    = "wc003-simulation"
      ManagedBy  = "terraform"
      Repository = "tgt-db-restore"
      Simulation = "wc003-phase2"
    }
  }
}
