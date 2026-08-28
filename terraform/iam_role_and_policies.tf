# Difference between Normal IAM roles vs. IRSA roles

# IAM Role (Normal way):
# Usually, EC2 nodes (worker nodes) get an IAM role. All pods running on that node share the same AWS permissions. Problem: You give more permissions than needed. Not secure.


# IRSA (IAM Roles for Service Accounts):
# Instead of giving the node a role, you give the pod a role. You create a service account in Kubernetes, attach it to the pod. AWS uses the pod’s OIDC token to let it assume the role.
# In this case, we are giving permissions to the pod, not the node.


# Something to note when defining policies;   "Effect": "Allow"  OR  Effect = "Allow" can be used. 
# They can be used interchangably
# JSON uses colons (:) and double quotes ("") 
# WHILE 
# Terraform HCL uses equals signs (=) without quotes for keys.



# The EKS control plane needs an IAM role to manage AWS resources on your behalf.
resource "aws_iam_role" "eks_cluster_role" {
  name = "eks_cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
        {
            Action = "sts:AssumeRole"
            Effect = "Allow"
            Principal = {
                Service = "eks.amazonaws.com"
            }
        }
    ]
  })
}


# Attach the required policies

# Grants the EKS control plane core permissions to create and manage the basic infrastructure supporting your Kubernetes cluster
    # Managing Elastic Network Interfaces (ENIs) for control plane-to-node communication.
    # Creating, describing, and deleting EC2 Security Groups for the cluster.
    # Interacting with Auto Scaling groups and Elastic Load Balancing (ELB) to route traffic to workloads.

resource "aws_iam_role_policy_attachment" "cluster_role_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role = aws_iam_role.eks_cluster_role.name
}



# Specifically allows the EKS VPC Resource Controller to manage specialized networking resources directly within your VPC.
    # Allocating and assigning private IP addresses or network interfaces.
    # Managing Security Groups for Pods (allowing you to assign specific AWS security groups directly to Kubernetes pods instead of the entire worker node).
    # Supporting Windows pooling and targeted network resource tracking.

resource "aws_iam_role_policy_attachment" "cluster_vpc_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role = aws_iam_role.eks_cluster_role.name
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# This is the role that the EC2 instances launched in the cluster will assume. It will have access to other aws services like s3, dynamoDB and SSM
resource "aws_iam_role" "eks_node_role" {
  name = "eks_node_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}


# Allows the node (EC2 instance) to join and operate inside the EKS cluster
resource "aws_iam_role_policy_attachment" "eks_worker" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}


# Allows the node to work with AWS VPC CNI plugin.
resource "aws_iam_role_policy_attachment" "eks_cni" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}


# This lets nodes pull container images
resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}


# This gives the nodes permissions required to work with AWS Systems Manager (SSM) like SSM agent messaging etc.
# It allows you to establish an interactive shell connection to instances in private subnets, 
resource "aws_iam_role_policy_attachment" "ssm_instance_core" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# The EKS web app will be deployed into a pod. Its best practice need to create a unique role for it. This will enforce least privilege. 
# IAM role used ONLY by the EKS web app Pod
resource "aws_iam_role" "eks_webapp_pod_role" {
  name = "eks-web-app-pod-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {Service = "pods.eks.amazonaws.com"}

        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
}


# Policy that allows the application to have access to get Cognito properties from SSM and can only carryout PUT, LIST, SCAN, QUERY and UPDATE actions on S3 and DynamoDB
resource "aws_iam_policy" "ssm_dynamodb_and_s3_access" {
  name        = "ssm_read_access_and_s3_access"
  description = "Allows pods to access SSM, DynamoDB, and S3"
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
      Effect   = "Allow",
      Action   = [
        "ssm:GetParameter", 
        "ssm:GetParameters"
      ],
      "Resource": [
          "${aws_ssm_parameter.cognito_user_pool_id.arn}",
          "${aws_ssm_parameter.cognito_client_id.arn}",
          "${aws_ssm_parameter.cognito_client_secret.arn}",
          "${aws_ssm_parameter.aws_cognito_user_pool_domain.arn}",
          "${aws_ssm_parameter.s3_bucket_name.arn}",
          "${aws_ssm_parameter.dynamodb_name.arn}",
          "${aws_ssm_parameter.region.arn}"
      ]
    },

    {
    "Effect": "Allow",
    "Action": [
        "s3:PutObject",
        "s3:ListBucket",

        "dynamodb:PutItem",
        "dynamodb:Scan",
        "dynamodb:Query",
        "dynamodb:UpdateItem",

      ],
    "Resource": [
        "${aws_s3_bucket.eks_platform_s3_bucket.arn}",
        "${aws_s3_bucket.eks_platform_s3_bucket.arn}/*",

        "${aws_dynamodb_table.eks_platform_requests.arn}",
        "${aws_dynamodb_table.eks_platform_requests.arn}/*"
    ]
    }

    ]
  })
}



# Attach necessary policies to the EKS node. 

# Allows node to access other aws services like ssm, s3 and DynamoDB
resource "aws_iam_role_policy_attachment" "eks_webapp_pod_s3_ssm_attachment" {
  role       = aws_iam_role.eks_webapp_pod_role.name
  policy_arn = aws_iam_policy.ssm_dynamodb_and_s3_access.arn
}


# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# The Cluster Auto Scaler will be deployed into a pod. Its best practice need to create a unique role for it. This will enforce least privilege. 
# IAM role used ONLY by the Cluster Autoscaler Pod
resource "aws_iam_role" "cluster_autoscaler" {
  name = "ClusterAutoscalerRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {Service = "pods.eks.amazonaws.com"}

        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
}



# Permissions required by Cluster Autoscaler to inspect and modify the AWS Auto Scaling Groups behind EKS node groups. It gives cluster autoscaler permission to scale nodes (in/out)
resource "aws_iam_policy" "cluster_autoscaler" {
  name = "ClusterAutoscalerPolicy"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",

          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:GetInstanceTypesFromInstanceRequirements",

          "eks:DescribeNodegroup",

          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]

        Resource = "*"
      }
    ]
  })
}



resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  role = aws_iam_role.cluster_autoscaler.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
  depends_on = [ aws_iam_policy.cluster_autoscaler ]
}


# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# The ALB controller will be deployed on a pod. Its best practice need to create a unique role for it. This will enforce least privilege. 
# IAM role used ONLY by the ALB Controller Pod
resource "aws_iam_role" "alb_controller" {
  name = "AlbControllerRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {Service = "pods.eks.amazonaws.com"}

        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
}


# I added a provider in te main.tf file to allow terraform access http
# Note the version here matches the eks controller image tag (version) as stated in the load_balacer_controller.tf file
data "http" "aws_lb_controller_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.13.4/docs/install/iam_policy.json"
}


# This is the load balancer policy. I defined it here so I can attach it to the iam role
resource "aws_iam_policy" "aws_lb_controller" {
  name        = "AWSLoadBalancerControllerIAMPolicy"
  description = "Policy for AWS Load Balancer Controller"

  policy = data.http.aws_lb_controller_policy.response_body
}


resource "aws_iam_role_policy_attachment" "lb_controller" {
  role = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.aws_lb_controller.arn
  depends_on = [ aws_iam_policy.aws_lb_controller ]
}



# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

output "cluster_iam_role" {
  value = aws_iam_role.eks_cluster_role.name
}

output "eks_node_iam_role" {
  value = aws_iam_role.eks_node_role.name
}

output "eks_webapp_role" {
  value = aws_iam_role.eks_webapp_pod_role.name
}

output "cluster_autoscaler_iam_role" {
  value = aws_iam_role.cluster_autoscaler.name
}

output "aws_load_balancer_controller" {
  value = aws_iam_role.alb_controller.name
}
