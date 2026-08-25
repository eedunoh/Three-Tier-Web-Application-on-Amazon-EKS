resource "aws_s3_bucket" "eks_platform_s3_bucket" {
    bucket = var.s3_bucket_name
}


# Setup s3 event notification to trigger lambda when files are added to the s3 bucket
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.eks_platform_s3_bucket.id

  lambda_function {
    lambda_function_arn = aws_sns_topic.eks_alerts.arn
    events              = ["s3:ObjectCreated:*"]      # Lambda is triggered when any event is created
  }

  depends_on = [aws_sns_topic_policy.allow_s3]     # Depends on the policy that gives permission to the s3 bucket to invoke SNS
}




output "s3_bucket_id" {
  value = aws_s3_bucket.eks_platform_s3_bucket.id
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.eks_platform_s3_bucket.arn
}