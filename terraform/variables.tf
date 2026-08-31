
# VPC and Subnets Variables
variable "region" {
  default     = "eu-north-1"
  description = "AWS region"
  type        = string
}

variable "vpc_name" {
  default     = "Cloud-Native-EKS-Platform-VPC"
  description = "VPC name"
  type        = string
}

variable "vpc_cidr" {
  default     = "10.0.0.0/16"
  description = "VPC Address/ CIDR block"
  type        = string
}

variable "az_count" {
  default     = 3
  description = "count of availabily zones in the region"
  type        = number
}

variable "public_subnet_cidr" {
  default     = ["10.0.1.0/24", "10.0.3.0/24", "10.0.5.0/24"]
  description = "list of all public subnet CIDR blocks"
  type        = list(string)
}

variable "private_subnet_cidr" {
  default     = ["10.0.2.0/24", "10.0.4.0/24", "10.0.6.0/24"]
  description = "list of all private subnet CIDR blocks"
  type        = list(string)
}

variable "route_table_cidr" {
  default     = "0.0.0.0/0"
  description = "route table CIDR block that directs traffic to and from internet gateway"
  type        = string
}

variable "availability_zone" {
  default = ["eu-north-1a", "eu-north-1b", "eu-north-1c"]
}


variable "admin_email" {
  default = "eedunoh@gmail.com"
  description = "administrator email"
  type = string
}

variable "user_pool_name" {
  default = "eks_platform_user_pool"
  description = "cognito user pool name"
  type = string
}


variable "user_pool_client_name" {
    default = "my-eks-platform"
    description = "my user pool client name"
    type = string
}

variable "s3_bucket_name" {
    default = "eks-platform-env-s3-bucket"
    description = "s3 bucket for my EKS platform"
    type = string
}


variable "dynamodb_name" {
    default = "eks_platform_requests"
    description = "EKS platform dynamodb storage name"
    type = string
}


variable "sns_name" {
    default = "eks_platform_sns"
    description = "sns notification for EKS platform"
    type = string
}