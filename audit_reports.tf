resource "aws_s3_bucket" "audit_reports" {
  bucket = var.audit_reports_bucket_name

  tags = {
    Name    = var.audit_reports_bucket_name
    Purpose = "Audit log reports"
  }
}

resource "aws_s3_bucket_public_access_block" "audit_reports" {
  bucket = aws_s3_bucket.audit_reports.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "audit_reports" {
  bucket = aws_s3_bucket.audit_reports.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit_reports" {
  bucket = aws_s3_bucket.audit_reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = "alias/aws/s3"
    }
    bucket_key_enabled = true
  }
}

data "aws_iam_policy_document" "audit_reports_tls_only" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.audit_reports.arn,
      "${aws_s3_bucket.audit_reports.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "audit_reports_tls_only" {
  bucket = aws_s3_bucket.audit_reports.id
  policy = data.aws_iam_policy_document.audit_reports_tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.audit_reports]
}
