terraform {
  backend "local" {}

  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}