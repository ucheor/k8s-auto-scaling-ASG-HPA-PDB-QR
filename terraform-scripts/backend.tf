terraform {
  backend "s3" {
    bucket       = "eks-autoscaling-ucheor" #replace with your bucket name
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}