variable "eks_cluster_name" {
  type    = string
  default = "auto_scaler"
}

variable "node_group_name" {
  type    = string
  default = "auto_scaler-node-group"
}

variable "eks_version" {
  type    = string
  default = "1.31"
}

variable "instance_types" {
  type    = string
  default = "t3.small"
}