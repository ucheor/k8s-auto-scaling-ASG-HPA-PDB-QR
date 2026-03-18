/*

#Using AWS EKS default security group - in production, specify routes

resource "aws_security_group" "eks_cluster" {
  name        = "${var.eks_cluster_name }-cluster-sg"
  description = "EKS cluster SG"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "eks_nodes" {
  name        = "${var.eks_cluster_name}-nodes-sg"
  description = "EKS worker nodes SG"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port                = 443
    to_port                  = 443
    protocol                 = "tcp"
    source_security_group_id = aws_security_group.eks_cluster.id
  }

  ingress {
    from_port         = 0
    to_port           = 65535
    protocol          = "tcp"
    self              = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
*/