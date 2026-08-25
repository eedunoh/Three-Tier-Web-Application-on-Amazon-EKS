#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# IMPORTANT!

# Confirm that the AWS principal pushing images to ECR (IAM user or IAM role) has sufficient permissions. 
# If it has AdministratorAccess (either attached directly or inherited through an IAM group), no additional ECR IAM policy is required. 
# Otherwise, attach a custom IAM policy (or an AWS-managed ECR policy) that grants the permissions required to push images to Amazon ECR.

# In my case, I authenticated GitHub Actions using an IAM user's access key. That IAM user belongs to the Admin group, which has AdministratorAccess.
# Therefore, I already have all the permissions needed to push Docker images to Amazon ECR.

# You do not need to create any ECR “infrastructure” before creating a repository. 
# The Amazon ECR private registry already exists by default in every AWS account and region – you can’t “create” it. 
# You simply add repositories to that registry.

# "IMMUTABLE" enforces a strict rule: once a tag is pushed, it is locked forever. Any subsequent push using the same tag will be rejected with an error. You cannot change what image that tag points to.
# Since this is not a real production environment, I will use "MUTABLE"




#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

resource "aws_ecr_repository" "eks_app_repository" {
  name = "eks_app"
  image_scanning_configuration {
    scan_on_push = true
  }
  force_delete = true
  image_tag_mutability = "MUTABLE"
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Output

output "eks_app_repo_url" {
  value = aws_ecr_repository.eks_app_repository.repository_url
}
