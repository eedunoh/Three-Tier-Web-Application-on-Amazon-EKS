terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Allows Terraform to manage Helm releases (like the cluster autoscaler and load balancer controller) as Terraform resources.
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.2.0"
    }

    # Allows Terraform to manage Kubernetes resources (like ServiceAccounts) directly, and must be configured with cluster authentication to connect to EKS.
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }

    # Enables Terraform to fetch data from HTTP(S) URLs. In my setup, it’s used to retrieve the AWS Load Balancer Controller IAM policy JSON from GitHub, so I don’t have to store it locally.
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}




# I encountered issues where Terraform couldn't authenticate to my Kubernetes cluster for Helm or Kubernetes resources like service accounts.
# This code configures both the Helm and Kubernetes providers to connect to Amazon EKS. It does two things:
# Fetches a temporary authentication token using the aws_eks_cluster_auth data source.
# Uses that token along with the cluster endpoint and CA certificate to authenticate both providers to Kubernetes.

data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.eks_cluster.name
}


# https://registry.terraform.io/providers/hashicorp/helm/latest/docs
provider "helm" {
  kubernetes = {
    host                   = aws_eks_cluster.eks_cluster.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.eks_cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

provider "kubernetes" {
  host                   = aws_eks_cluster.eks_cluster.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.eks_cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}




# Configure provider
provider "aws" {
  region = var.region
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Create VPC, Public, Private subnets and remote backend for terraform state file storage

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  tags = {
    name = var.vpc_name
  }
}


resource "aws_subnet" "public" {
  count                   = var.az_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr[count.index]
  availability_zone       = var.availability_zone[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "public subnet ${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count                   = var.az_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr[count.index]
  availability_zone       = var.availability_zone[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "private subnet ${count.index + 1}"
  }
}


# This S3 must already exist in your account. You can create it manually before other infrastructures so that GitHub Actions/terraform can use it to store state files and then provision infra.
terraform {
  backend "s3" {
    bucket       = "eks-platform-terraform-state-bucket-fyi"
    key          = "eks-platform/terraform.tfstate" 
    region       = "eu-north-1"
    encrypt      = true
    
    # This activates native S3 locking instead of DynamoDB
    use_lockfile = true 
  }
}



# Use this AWS CLI code to create the s3 bucket above;

# aws s3api create-bucket \
#   --bucket eks-platform-terraform-state-bucket-fyi \
#   --region eu-north-1 \
#   --create-bucket-configuration LocationConstraint=eu-north-1


#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Create Internet Gateway and Public subnet Route table + attach them
resource "aws_internet_gateway" "eks_platform_igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    name = "eks platform igw"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = var.route_table_cidr
    gateway_id = aws_internet_gateway.eks_platform_igw.id
  }

  tags = {
    name = "eks platform route table"
  }
}

resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Create Elastic IPs for each NAT gateway, Private subnet route tables + attach them
resource "aws_eip" "nat_eip" {
  count  = var.az_count
  domain = "vpc"
}

resource "aws_nat_gateway" "eks_platform_nat" {
  count         = var.az_count
  subnet_id     = aws_subnet.public[count.index].id
  allocation_id = aws_eip.nat_eip[count.index].id
  depends_on    = [aws_internet_gateway.eks_platform_igw]
}

resource "aws_route_table" "private_route_table" {
  count  = var.az_count
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.eks_platform_nat[count.index].id
  }
}

resource "aws_route_table_association" "private" {
  count          = var.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private_route_table[count.index].id
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Output

output "vpc_name_id" {
  value = aws_vpc.main.id
}

output "public_subnets" {
  value = aws_subnet.public[*].id
}

output "private_subnets" {
  value = aws_subnet.private[*].id
}

# I need a csv output that will be used in airflow_init task command
output "private_subnet_ids_csv" {
  value = join(",", aws_subnet.private[*].id)
}