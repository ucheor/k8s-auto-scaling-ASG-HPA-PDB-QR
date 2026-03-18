Add to GitHub Secrets

secrets.AWS_REGION
secrets.AWS_ROLE_ARN (# OIDC ROLE)


To set up your access through Access Entry
update_kubeconfig_command = "aws eks update-kubeconfig --region *** --name dev-cluster"
aws sts get-caller-identity

    aws eks create-access-entry \
    --cluster-name dev-cluster \
    --principal-arn <YOUR_PRINCIPAL_ARN> \                          #your principal arn example - <arn:aws:iam::826432:user/mir>
    --type STANDARD

    aws eks associate-access-policy \
    --cluster-name dev-cluster \
    --principal-arn <YOUR_PRINCIPAL_ARN> \                          #your principal arn example - <arn:aws:iam::826432:user/mir>
    --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
    --access-scope type=cluster
