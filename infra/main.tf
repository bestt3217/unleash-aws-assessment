terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

module "auth" {
  source = "./modules/auth"

  providers = {
    aws = aws
  }
}

module "compute_us" {
  source    = "./modules/compute"
  providers = { aws = aws }

  region              = var.region_primary
  user_pool_arn       = module.auth.user_pool_arn
  user_pool_client_id = module.auth.client_id
  email               = var.email
  repo_url            = var.repo_url
}

module "compute_eu" {
  source    = "./modules/compute"
  providers = { aws = aws.eu }

  region              = var.region_secondary
  user_pool_arn       = module.auth.user_pool_arn
  user_pool_client_id = module.auth.client_id
  email               = var.email
  repo_url            = var.repo_url
}

output "user_pool_id" {
  value       = module.auth.user_pool_id
  description = "Cognito User Pool ID (primary region)"
}

output "client_id" {
  value       = module.auth.client_id
  description = "Cognito User Pool Client ID (primary region)"
}

output "user_pool_arn" {
  value       = module.auth.user_pool_arn
  description = "Cognito User Pool ARN (used by API authorizers in both regions)"
}

output "api_url_us" {
  value = module.compute_us.api_url
}

output "api_url_eu" {
  value = module.compute_eu.api_url
}