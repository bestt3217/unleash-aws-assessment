provider "aws" {
  region = var.region_primary
}

provider "aws" {
  alias  = "eu"
  region = var.region_secondary
}