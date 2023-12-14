variable "stack_name" {
  description = "A unique name for the stack that is being spun up."
  type        = string
}

variable "region" {
  default     = "us-east-1"
  description = "AWS Region to deploy into"
}

variable "unified_auth_jwks_endpoint" {
  description = "The Unified Auth JWKS endpoint to utilize for verifying the access token passed to the API Gateway."
  type        = string
  default     = "https://rxss-playground.rxss-dev.auth0app.com/.well-known/jwks.json"
}

variable "is_localstack_deploy" {
  description = "Boolean stating whether the stack is being deployed via tflocal and LocalStack for local development."
  type        = bool
  default     = false
}
