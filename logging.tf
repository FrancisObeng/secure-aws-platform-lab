# Look up our own account ID (used for unique names and policies)
data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  trail_name = "${var.project_name}-trail"
  trail_arn  = "arn:aws:cloudtrail:${var.aws_region}:${local.account_id}:trail/${local.trail_name}"
  logs_arn   = "arn:aws:logs:${var.aws_region}:${local.account_id}:*"
}

# --- S3 bucket that stores the audit logs and VPC flow logs ---
resource "aws_s3_bucket" "logs" {
  #checkov:skip=CKV_AWS_144:Account is SCP region-locked to us-east-2; cross-region replication is not possible
  #checkov:skip=CKV_AWS_18:This is the central log bucket; access-logging it would require another bucket (recursive)
  #checkov:skip=CKV2_AWS_62:Event notifications not needed for an audit-log bucket
  #checkov:skip=CKV_AWS_145:SSE-S3 (AES256) in use; customer-managed KMS planned as a stretch goal
  bucket        = "${var.project_name}-logs-${local.account_id}"
  force_destroy = true # lab only: lets terraform destroy remove a bucket that has logs in it

  tags = { Name = "${var.project_name}-logs" }
}

# Block ALL public access
resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Encrypt everything stored in the bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Keep old versions of files (protects against overwrite or deletion)
resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Lifecycle: expire old logs so storage doesn't grow forever (fixes CKV2_AWS_61)
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Bucket policy: only CloudTrail and VPC Flow Logs may write here, and only over HTTPS
resource "aws_s3_bucket_policy" "logs" {
  bucket     = aws_s3_bucket.logs.id
  depends_on = [aws_s3_bucket_public_access_block.logs]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "CloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.logs.arn
        Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn } }
      },
      {
        Sid       = "CloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.logs.arn}/AWSLogs/${local.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = local.trail_arn
          }
        }
      },
      {
        Sid       = "FlowLogsAclCheck"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.logs.arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account_id }
          ArnLike      = { "aws:SourceArn" = local.logs_arn }
        }
      },
      {
        Sid       = "FlowLogsWrite"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.logs.arn}/vpc-flow-logs/AWSLogs/${local.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "aws:SourceAccount" = local.account_id
          }
          ArnLike = { "aws:SourceArn" = local.logs_arn }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })
}

# --- CloudTrail: the audit log itself ---
resource "aws_cloudtrail" "main" {
  #checkov:skip=CKV_AWS_35:SSE-S3 encryption in use; customer-managed KMS planned as a stretch goal
  #checkov:skip=CKV_AWS_252:Per-log-file SNS notifications would be noise; alarms handled by CloudWatch
  #checkov:skip=CKV2_AWS_10:Logs centralized in S3 with integrity validation; CloudWatch Logs integration deferred (cost/complexity)
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.logs.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  depends_on = [aws_s3_bucket_policy.logs]

  tags = { Name = local.trail_name }
}

# --- VPC Flow Logs: record network traffic metadata (fixes CKV2_AWS_11) ---
resource "aws_flow_log" "vpc" {
  vpc_id                   = aws_vpc.main.id
  traffic_type             = "ALL"
  log_destination_type     = "s3"
  log_destination          = "${aws_s3_bucket.logs.arn}/vpc-flow-logs/"
  max_aggregation_interval = 600

  depends_on = [aws_s3_bucket_policy.logs]

  tags = { Name = "${var.project_name}-vpc-flow-logs" }
}
