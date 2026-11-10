terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Remote state: stored encrypted and versioned in S3 instead of on this PC.
  # use_lockfile = S3-native locking, so two runs can't change state at once.
  backend "s3" {
    bucket       = "secure-lab-tfstate-227046208727"
    key          = "secure-aws-platform-lab/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}
