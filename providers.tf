terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.30.0" # Allows only patch updates (e.g., 5.30.1, 5.30.2)
    }
  }
}

provider "aws" {
  region  = "us-west-2"
}
