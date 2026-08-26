# There is an important note at the end of this file. Read It!

# Install Kubernetes Load Balancer Controller. Load balancer controller is required to create the application load balancer which will act as an entry point for traffic directed to the app and grafana

# The Load balancer controller will be deployed into a pod. Its best practice to create a unique role for it. This will enforce least privilege. 

# Install the EKS Pod Identity Agent. This allows EKS Pods to assume IAM roles through Pod Identity.
resource "aws_eks_addon" "controller_pod_identity_agent" {
  cluster_name = aws_eks_cluster.eks_cluster.name
  addon_name   = "controller-eks-pod-identity-agent"
}


# Terraform creates the eks pod identity association for the load balancer controller. Pod Identity will attach the iam role and permission to the pod itself and not the node the pod is scheduled on.
resource "aws_eks_pod_identity_association" "lb_controller" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  namespace       = "kube-system"

  # must match Helm serviceAccount.name
  service_account = "aws-load-balancer-controller"

  role_arn = aws_iam_role.alb_controller.arn

  depends_on = [
    aws_eks_addon.controller_pod_identity_agent,
    aws_iam_role_policy_attachment.lb_controller
  ]
}


# Terraform manages the Helm installation of load balancer contoller. Helm creates the Deployment, ServiceAccount, RBAC resources, etc.

resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"

  # Stable chart version (pins the installation)
  # Each Helm chart is independently versioned by its own maintainers. The version numbers have nothing to do with the software they deploy or each other.
  # Think of it like: 
  # Cluster Autoscaler chart: maintained by the Kubernetes autoscaler team, they happen to use versions like 9.x. 
  # AWS Load Balancer Controller chart: maintained by AWS EKS team, they use versions like 1.x.
  # Check compatible versions here: helm search repo eks/aws-load-balancer-controller --versions

  version    = "1.13.4"
  namespace  = "kube-system"

  values = [
      yamlencode({

        clusterName = aws_eks_cluster.eks_cluster.name

        # IMPORTANT: Use a load balancer controller version compatible with your EKS. Check compatible versions here: helm search repo eks/aws-load-balancer-controller --versions
        image = {
          tag = "v2.13.4"
        }


        # Helm creates the ServiceAccount. This MUST match the ServiceAccount used in aws_eks_pod_identity_association above.
        rbac = {
          serviceAccount = {
            create = true
            name   = "aws-load-balancer-controller"
          }
        }


        # crds.create = true is a Helm chart value for the AWS Load Balancer Controller. It tells Helm to install the Custom Resource Definitions (CRDs) that the controller needs.
        # The controller uses Kubernetes custom resources like TargetGroupBinding, IngressClassParams, and others to manage load balancers. 
        # If the CRDs are not present, the controller will fail to start or function because it can't create those custom resources.
        # By default, the AWS Load Balancer Controller Helm chart sets crds.create = true, but being explicit ensures the CRDs are installed as part of the release. 
        # Without them, you might see errors like no matches for kind "TargetGroupBinding". So adding crds.create = true ensures the controller has all the necessary resource definitions.
        crds = {
        create = true
        }

      })
    ]

  depends_on = [
    aws_eks_pod_identity_association.lb_controller,
    aws_eks_cluster.eks_cluster,
     aws_eks_node_group.general_and_monitoring,
     aws_eks_node_group.app_worker
  ]
}
