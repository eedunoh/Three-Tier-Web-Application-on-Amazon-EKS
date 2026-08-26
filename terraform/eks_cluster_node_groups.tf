# There is an important note at the end of this file. Read It!

# In this project I will use AWS-managed EKS and Kubernetes Cluster Autoscaler. 

# I wont be using taint and tolerations because I encountered an issue where custom taint and tolerations affected the functioning of the cluster's CoreDNS.

# Create the EKS Cluster
resource "aws_eks_cluster" "eks_cluster" {
  name = "eks_cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.35"

  vpc_config {
    subnet_ids = aws_subnet.private[*].id

    # Allow access from within VPC
    endpoint_private_access = true 


    # With endpoint_public_access = true, Kubernetes clusters are accessible publicly to enable remote kubectl administration without VPNs 
    # and simplify CI/CD integrations by removing the need for complex VPC peering, which optimizes development and testing by accelerating deployment speeds in sandbox environments. 
    
    # In production, companies block public internet access (endpoint_public_access = false) to the API server and route administrative traffic through internal VPC networks using AWS Client VPNs or bastion hosts. 
    # Meanwhile, user application traffic is kept completely separate, routing exclusively through secure gateways like public Application Load Balancers down to pods isolated in private subnets.
    endpoint_public_access = true

    security_group_ids = [aws_security_group.eks_cluster.id]
  }  


  # Enable control panel logging. Note, AWS will manage the control panel, so we need to monitor what is happening there.
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]


  # This is to ensure that the policies are attached before the cluster is created
  depends_on = [ 
    aws_iam_role_policy_attachment.cluster_role_policy,
    aws_iam_role_policy_attachment.cluster_vpc_controller
  ]
  
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# I will define the managed node groups. I will have multiple node groups optimized for different workload types.

# You don't have to create/select/manage the instance profile, AMI, launch template yourself. AWS does that. 
# AWS explicitly says that when you create a managed node group without specifying a custom AMI, EKS selects the appropriate EKS-optimized AMI.
# However, for more control over the node configuration; custom AMIs, additional storage, user data scripts. I can use a launch template and then attach instance profile generated using the node_ian_role, but I won't implement that in this project.

# This is a general purpose node for clutser tools and monitoring like prometheus and grafana
resource "aws_eks_node_group" "general_and_monitoring" {
  cluster_name = aws_eks_cluster.eks_cluster.name
  node_group_name = "general-and-monitoring-node"

  # Notice we used node iam_role here rather than instace profile, this is because when using AWS managed EKS, AWS handles the instance profile generation from the node iam role
  node_role_arn = aws_iam_role.eks_node_role.arn
  subnet_ids = aws_subnet.private[*].id

  instance_types = ["t3.large"]
  capacity_type = "ON_DEMAND"


  scaling_config {
    desired_size = 1
    max_size = 2
    min_size = 1
  }


  # Only drain one node at a time during updates
  update_config {
    max_unavailable = 1
  }


  # This is to ensure that the policies are attached before the node is created
  depends_on = [ 
    aws_iam_role_policy_attachment.ecr_readonly,
    aws_iam_role_policy_attachment.eks_cni,
    aws_iam_role_policy_attachment.ssm_instance_core,
    aws_iam_role_policy_attachment.eks_node_s3_ssm_attachment,
    aws_iam_role_policy_attachment.eks_worker
  ]


  # I want to ensure that workloads are not randomly placed on just any node. Example: prometheus and grafana should ONLY run on the general_and_monitoring node and not the app_worker node.
  # I will use labels and taints to implement that. In terraform, I will define label and taint for each node and in my deployment manifest, I will configure the workload to match appropriate labels.

  # Label and taints work in tandem. If I have only label, Prometheus could be attracted to that node, but other workloads could also be scheduled there and they may use up the intened resources.


  # Labels identify which workloads the node is intended for. Put my workload here.
  labels = {
    role = "general_and_monitoring"
  }

}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# This node group is only for the app
resource "aws_eks_node_group" "app_worker" {
  cluster_name = aws_eks_cluster.eks_cluster.name
  node_group_name = "app-worker-node"

  # Notice we used node iam_role here rather than instace profile, this is because when using AWS managed EKS, AWS handles the instance profile generation from the node iam role
  node_role_arn = aws_iam_role.eks_node_role.arn
  subnet_ids = aws_subnet.private[*].id

  instance_types = ["t3.large"]
  capacity_type = "ON_DEMAND"

  scaling_config {
    desired_size = 1
    max_size = 2
    min_size = 1
  }


  # Only drain one node at a time during updates
  update_config {
    max_unavailable = 1
  }


  # This is to ensure that the policies are attached before the node is created
  depends_on = [ 
    aws_iam_role_policy_attachment.ecr_readonly,
    aws_iam_role_policy_attachment.eks_cni,
    aws_iam_role_policy_attachment.ssm_instance_core,
    aws_iam_role_policy_attachment.eks_node_s3_ssm_attachment,
    aws_iam_role_policy_attachment.eks_worker
  ]


  # Labels identify which workloads the node is intended for. Put my workload here.
  labels = {
    role = "app_worker"
  }

}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

output "eks_cluster_name" {
  value = aws_eks_cluster.eks_cluster.name
}







#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# IMPORTANT:

# This documentation was useful: https://oneuptime.com/blog/post/2026-02-23-create-eks-cluster-managed-node-groups-terraform/view#managed-node-groups

# Amazon EKS offers four compute management tiers that transition from manual control to full automation; 
# 1. In Self-Managed Nodes, your team manually creates and configures the Auto Scaling Groups (ASGs), Launch Templates, and EC2 instances, giving you absolute control over custom operating systems at the cost of high maintenance, manual patching, and complex cluster upgrades. 
# 2. Managed Node Groups shift the operational burden by letting AWS automatically generate, update, and patch the ASGs and Launch Templates, though you are still responsible for choosing instance sizes and tuning the Kubernetes Cluster Autoscaler. 
# 3. EKS Auto Mode completely removes ASGs and Launch Templates from your account, replacing them with a built-in, invisible version of Karpenter that automatically provisions and right-sizes standard EC2 instances based on active pod demands while maintaining full Kubernetes compatibility for DaemonSets, Spot instances, and GPUs. 
# 4. Finally, AWS Fargate eliminates the concept of EC2 instances, ASGs, and templates entirely by deploying each individual pod into its own isolated, serverless micro-VM, providing maximum security isolation but restricting features like DaemonSets and GPUs while costing more at scale.

# In both EKS Auto Mode and AWS Fargate, the Kubernetes Cluster Autoscaler is completely deprecated and not used. Because AWS handles infrastructure scaling natively behind the scenes, you do not need to install, configure, or maintain the Cluster Autoscaler deployment.

