# Bootstrap: one-time, long-lived resources the main stack depends on.
# Holds the remote state bucket. Do NOT destroy each session.
# Its own state stays local on purpose (chicken-and-egg: it creates the bucket).
# GitHub OIDC design: see github-oidc.tf.example (blocked by org SCP).

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"

  default_tags {
    tags = {
      Project   = "secure-lab"
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  state_bucket = "secure-lab-tfstate-${data.aws_caller_identity.current.account_id}"
}

# --- Remote state bucket ---
resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV_AWS_144:Account is SCP region-locked to us-east-2; cross-region replication not possible
  #checkov:skip=CKV_AWS_18:Small lab state bucket; API access already recorded by CloudTrail
  #checkov:skip=CKV2_AWS_62:Event notifications not needed for a state bucket
  #checkov:skip=CKV_AWS_145:SSE-S3 in use; customer-managed KMS planned as a stretch goal
  bucket = local.state_bucket

  # Safety net: Terraform refuses to delete this bucket
  lifecycle {
    prevent_destroy = true
  }

  tags = { Name = "secure-lab-tfstate" }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versioning = every old copy of the state is kept, so a bad change can be rolled back
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket     = aws_s3_bucket.state.id
  depends_on = [aws_s3_bucket_public_access_block.state]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

output "state_bucket" {
  value = aws_s3_bucket.state.id
}
