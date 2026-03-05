variable "region" {
  description = "Region this compute stack is deployed into"
  type        = string
}

variable "user_pool_arn" {
  description = "Cognito user pool ARN (from us-east-1) for API authorizer"
  type        = string
}

variable "user_pool_client_id" {
  description = "Cognito user pool client id (audience for JWT authorizer)"
  type        = string
}

variable "email" {
  description = "Email to include in SNS verification payload"
  type        = string
}

variable "repo_url" {
  description = "Repo URL to include in SNS verification payload"
  type        = string
}

variable "sns_topic_arn" {
  description = "Unleash live verification SNS topic ARN (fixed by assessment)"
  type        = string
  default     = "arn:aws:sns:us-east-1:637226132752:Candidate-Verification-Topic"
}
