resource "aws_sns_topic" "eks_alerts" {
  name = var.sns_name
}


resource "aws_sns_topic_subscription" "email_sub" {
  topic_arn = aws_sns_topic.eks_alerts.arn
  protocol  = "email"

  # Admin email address stored as a variable
  endpoint  = var.admin_email 
}


# Set tge SNS access policy to S3 to publish to SNS topic. Read more examples here: https://oneuptime.com/blog/post/2026-02-12-s3-event-notifications-sqs-sns/view
resource "aws_sns_topic_policy" "allow_s3" {
  arn = aws_sns_topic.eks_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "AllowS3Publish"
        Effect = "Allow"

        Principal = {
          Service = "s3.amazonaws.com"
        }

        Action   = "sns:Publish"
        Resource = "${aws_sns_topic.eks_alerts.arn}"

        Condition = {
          ArnLike = {
            "aws:SourceArn" = "${aws_s3_bucket.eks_platform_s3_bucket.arn}"
          }
        }
      }
    ]
  })
}


output "sns_arn" {
  value = aws_sns_topic.eks_alerts.arn
}