variable "email" {
  type        = string
  description = "Email used for SNS payload"
}

variable "repo_url" {
  type        = string
  description = "Repo URL used for SNS payload"
}

variable "region_primary" {
  type    = string
  default = "us-east-1"
}

variable "region_secondary" {
  type    = string
  default = "eu-west-1"
}