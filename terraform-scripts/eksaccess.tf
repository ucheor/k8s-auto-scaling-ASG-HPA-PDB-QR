##---Gives access to apply changes (Helm deployment) inside the k8s cluster

# 1. Get the current STS identity (the assumed role session)
data "aws_caller_identity" "current" {}

# 2. Extract the actual IAM Role ARN from the STS session
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

# Create the entry using the dynamic identity
resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = data.aws_iam_session_context.current.issuer_arn
  type          = "STANDARD"
}

# Associate Admin policy to the dynamic identity
resource "aws_eks_access_policy_association" "github_admin" {
  cluster_name  = aws_eks_cluster.main.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = data.aws_iam_session_context.current.issuer_arn

  access_scope {
    type = "cluster"
  }
}
