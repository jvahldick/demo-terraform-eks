### ### ### ### ### ###
### EKS Cluster
### ### ### ### ### ###
variable "cluster_name" {
  description = "Name of the cluster"
}

variable "cluster_version" {
  description = "Version of the kubernetes cluster"
  default     = "1.21"
}

### ### ### ### ### ###
### AWS
### ### ### ### ### ###
variable "aws_region" {}

variable "aws_profile" {
  description = "AWS profile that will be used to create the resources in the AWS cluster"
  default     = "default"
}

### ### ### ### ### ###
### Network
### ### ### ### ### ###
variable "main_network_block" {
  type        = string
  description = "Base CIDR block to be used in our VPC."
  default     = "10.0.0.0/16"
}

variable "subnet_prefix_extension" {
  type        = number
  description = "CIDR block bits extension to calculate CIDR blocks of each subnetwork."
  default     = 4
}

variable "zone_offset" {
  type        = number
  description = "CIDR block bits extension offset to calculate Public subnets, avoiding collisions with Private subnets."
  default     = 8
}

variable "iam_role_arn_cluster" {
  type        = string
  description = "ARN role to be used in the cluster"
}

variable "iam_role_arn_nodes" {
  type        = string
  description = "ARN role to be used in the cluster nodes"
}
