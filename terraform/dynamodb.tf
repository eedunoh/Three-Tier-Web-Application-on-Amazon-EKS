resource "aws_dynamodb_table" "eks_platform_requests" {
  name         = var.dynamodb_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "username"
  range_key = "request_date"

  attribute {
    name = "username"
    type = "S"
  }

  attribute {
    name = "request_date"
    type = "S"
  }

  # other attributes will be added automatically when inserting items — no need to define them here unless using them in indexes
  
  stream_enabled   = true                  # Enable dynamodb stream
  stream_view_type = "NEW_AND_OLD_IMAGES"  # Options: KEYS_ONLY | NEW_IMAGE | OLD_IMAGE | NEW_AND_OLD_IMAGES


  tags = {
    Environment = "dev"
  }
}