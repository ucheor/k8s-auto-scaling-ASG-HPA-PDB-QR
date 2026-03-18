output "update_kubeconfig_command" {
  description = "Run this command to connect your local terminal to the cluster"
  value       = "aws eks update-kubeconfig --region us-east-1 --name ${var.eks_cluster_name}"
}
