terraform {
  required_version = ">= 1.8.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.61.0"
    }
  }

  # The disposable environment intentionally uses bounded local state. It is
  # never a production state file and must not be copied into the repository.
  backend "local" {
    path = "state/disposable.tfstate"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "hyfens"
      Environment = var.environment_name
      ManagedBy   = "opentofu"
      Scope       = "disposable-task78"
    }
  }
}
