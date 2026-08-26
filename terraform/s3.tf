resource "aws_s3_bucket" "eks_platform_s3_bucket" {
    bucket = var.s3_bucket_name

    force_destroy = true
}


# Setup s3 event notification to trigger SNS when files are added to the s3 bucket
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.eks_platform_s3_bucket.id

    topic {
    topic_arn     = aws_sns_topic.eks_alerts.arn
    events        = ["s3:ObjectCreated:*"]

  }

  depends_on = [aws_sns_topic_policy.allow_s3]     # Depends on the policy that gives permission to the s3 bucket to invoke SNS
}




output "s3_bucket_id" {
  value = aws_s3_bucket.eks_platform_s3_bucket.id
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.eks_platform_s3_bucket.arn
}