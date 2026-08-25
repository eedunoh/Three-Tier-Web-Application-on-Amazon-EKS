# There is an important note at the end of this file. Read It!

# Install Kubernetes Cluster Autoscaler. 

# The Cluster Auto Scaler is a software and will be deployed into a pod. Its best practice to create a unique role for it. This will enforce least privilege. 

# Install the EKS Pod Identity Agent. This allows EKS Pods to assume IAM roles through Pod Identity.
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.eks_cluster.name
  addon_name   = "eks-pod-identity-agent"
}


# Terraform creates the eks pod identity association for the cluster auto scaler. Pod Identity will attach the iam role and permission to the pod itself and not the node the pod is scheduled on.
resource "aws_eks_pod_identity_association" "cluster_autoscaler" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  namespace       = "kube-system"
  service_account = "cluster-autoscaler"

  role_arn = aws_iam_role.cluster_autoscaler.arn

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.cluster_autoscaler
  ]
}


# Terraform manages the Helm installation of Cluster Autoscaler. Helm creates the Deployment, ServiceAccount, RBAC resources, etc.

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"

  # Example stable chart version (pins the installation)
  version    = "9.46.0" 
  namespace  = "kube-system"

  set = [

    # IMPORTANT: Use a Cluster Autoscaler version compatible with your EKS Kubernetes version. 
    { 
      name = "image.tag" 
      value = "v1.35.0" 
    },

    # Tell CA which EKS cluster it manages.
    {
      name  = "autoDiscovery.clusterName"
      value = aws_eks_cluster.eks_cluster.name
    },

    # The node I want to place the Cluster Autoscaler on.
    # Important: this does not mean Cluster Autoscaler can only scale the monitoring node group. The CA Pod can run on the monitoring node while managing/scaling your app and monitoring node groups through AWS APIs.
    {
      name  = "nodeSelector.role"
      value = aws_eks_node_group.general_and_monitoring.node_group_name
    },

    # AWS region.
    {
      name  = "awsRegion"
      value = var.region
    },

    # Helm creates the ServiceAccount. This MUST match the ServiceAccount used in aws_eks_pod_identity_association above.
    {
      name  = "rbac.serviceAccount.create"
      value = "true"
    },
    {
      name  = "rbac.serviceAccount.name"
      value = "cluster-autoscaler"
    },

    # Optional tuning.
    {
      name  = "extraArgs.balance-similar-node-groups"
      value = "true"
    },

    # Allows Cluster Autoscaler to consider nodes running system Pods for scale-down.
    {
      name  = "extraArgs.skip-nodes-with-system-pods"
      value = "false"
    },

      # A node must be unneeded for 10 minutes before Cluster Autoscaler considers removing it.
    {
      name  = "extraArgs.scale-down-unneeded-time"
      value = "10m"
    }
  ]

  depends_on = [
    aws_eks_pod_identity_association.cluster_autoscaler,
    aws_eks_cluster.eks_cluster,
     aws_eks_node_group.general_and_monitoring,
     aws_eks_node_group.app_worker
  ]
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# AWS Auto Scaling Group (ASG): Maintains the desired number of EC2 instances. Example: min = 1, desired = 2, max = 5. The ASG itself does NOT understand Kubernetes pods.

# Kubernetes Cluster Autoscaler: Watches for unschedulable pods and underutilized nodes, then adjusts the desired size of existing EKS node groups. Example: 1 → 2 nodes or 2 → 1 node.
# EKS Node Group manages a group of EKS worker nodes and uses an underlying ASG for the EC2 instances. Read more here: https://docs.aws.amazon.com/eks/latest/best-practices/cas.html
# Traditional EKS scaling: Pods → Cluster Autoscaler → Managed Node Group → ASG → EC2


# Karpenter: Watches for unschedulable pods and determines what EC2 capacity is needed based on workload requirements and configured constraints.
# If existing nodes have enough capacity, Pod uses existing node. If existing nodes do not have enough capacity, Karpenter provisions a new EC2 node. Karpenter can also consolidate/remove nodes when capacity is no longer needed. 
# Therefore, Karpenter performs autoscaling based on workload demand, but it does NOT do it through the traditional ASG min/desired/max model. It can replace the traditional Cluster Autoscaler + Node Group scaling mechanism, and Karpenter-provisioned nodes do NOT require an ASG.
# Karpenter model: Pods → Karpenter → EC2 Node


# ECS Capacity Provider: Connects ECS task demand to compute capacity. # ECS Capacity Provider is conceptually similar to Cluster Autoscaler/Karpenter because it responds to workload demand, but it is an ECS mechanism.
# ECS on EC2: ECS Tasks → Capacity Provider → ASG → EC2
# ECS Fargate: ECS Tasks → Capacity Provider → Fargate (No ASG required)


# NOTE SUMMARY:
# Cluster Autoscaler + EKS Managed Node Group: ASG is involved.
# Karpenter: ASG is NOT required for Karpenter-provisioned nodes.
# ECS Capacity Provider + EC2: ASG is typically involved.
# ECS Capacity Provider + Fargate: No ASG required.