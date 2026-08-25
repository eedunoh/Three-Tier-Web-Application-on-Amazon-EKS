# When you use AWS-managed EKS, AWS automatically creates and manages a hidden "Cluster security group" for you. 
# This managed group automatically allows full communication between the control plane and your managed node groups.

# Create a secondary security group for the cluster
resource "aws_security_group" "eks_cluster" {
  name_prefix = "eks cluster security group"
  description = "Egress"

  vpc_id = aws_vpc.main.id

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# Create a security group for eks nodes

resource "aws_security_group" "eks_node" {
  name        = "eks node server security group"
  description = "Allow HTTP"

  vpc_id = aws_vpc.main.id

  # Allow nodes to communicate with each other internally
  ingress {
    description = "Allow node-to-node communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description = "node server ingress"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]    # we can modify this rule to allow traffic from ONLY authorized IP addresses to achieve stricter security.
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}