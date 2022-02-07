data "aws_ami" "eks_default" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amazon-eks-node-${var.cluster_version}-v*"]
  }
}

data "aws_availability_zones" "available_azs" {
  state = "available"
}

locals {
  project_name = "demo-project"

  private_subnets = [
  # this loop will create a one-line list as ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20", ...]
  # with a length depending on how many Zones are available
  for zone_id in data.aws_availability_zones.available_azs.zone_ids :
  cidrsubnet(var.main_network_block, var.subnet_prefix_extension, tonumber(substr(zone_id, length(zone_id) - 1, 1)) - 1)
  ]

  public_subnets = [
  # this loop will create a one-line list as ["10.0.128.0/20", "10.0.144.0/20", "10.0.160.0/20", ...]
  # with a length depending on how many Zones are available
  # there is a zone Offset variable, to make sure no collisions are present with private subnet blocks
  for zone_id in data.aws_availability_zones.available_azs.zone_ids :
  cidrsubnet(var.main_network_block, var.subnet_prefix_extension, tonumber(substr(zone_id, length(zone_id) - 1, 1)) + var.zone_offset - 1)
  ]

  tags = {
    Project     = local.project_name
    Description = "Demo EKS"
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = local.project_name
  cidr = "10.0.0.0/16"

  azs             = flatten(data.aws_availability_zones.available_azs.names)
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = 1
  }

  tags = local.tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "18.4.0"

  cluster_name                    = var.cluster_name
  cluster_version                 = var.cluster_version
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_irsa = false

  create_iam_role = false
  iam_role_arn    = var.iam_role_arn_cluster

  eks_managed_node_group_defaults = {
    ami_type       = "AL2_x86_64"
    disk_size      = 20
    instance_types = ["t3.small", "t2.small"]
  }

  tags = local.tags
}

module "eks_managed_node_group_with_custom_ami" {
  source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"

  name            = "managed-eks-node-with-custom-ami"
  use_name_prefix = true

  create_iam_role = false
  iam_role_arn    = var.iam_role_arn_nodes

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  min_size     = 1
  max_size     = 1
  desired_size = 1

  cluster_name = var.cluster_name

  enable_bootstrap_user_data = true

  create_launch_template  = false
  launch_template_name    = aws_launch_template.external.name
  launch_template_version = aws_launch_template.external.default_version

  capacity_type        = "SPOT"
  disk_size            = 20
  force_update_version = true
  instance_types       = ["t3.small", "t2.small"]

  # these labels add also labels to the node
  labels = {
    my-label-1 = "value-1"
    my-label-2 = "value-2"
  }

  tags = local.tags
}


resource "aws_launch_template" "external" {
  name_prefix            = "custom-ami-"
  update_default_version = true

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 20
      volume_type           = "gp2"
      delete_on_termination = true
    }
  }

  network_interfaces {
    delete_on_termination = true
  }

  image_id  = data.aws_ami.eks_default.image_id
  user_data = base64encode(templatefile(
    "${path.module}/templates/linux_user_data.tpl",
    {
      cluster_name              = var.cluster_name
      cluster_auth_base64       = module.eks.cluster_certificate_authority_data
      cluster_endpoint          = module.eks.cluster_endpoint
      cluster_service_ipv4_cidr = var.main_network_block

      pre_bootstrap_user_data = <<-EOT
      export CONTAINER_RUNTIME="containerd"
      export KUBELET_EXTRA_ARGS=" --node-labels=your-label=value-of-the-label "
      EOT

      bootstrap_extra_args     = " --container-runtime containerd --kubelet-extra-args '--node-labels=your-label=value-of-the-label' "
      post_bootstrap_user_data = ""
    }
  ))


  tag_specifications {
    resource_type = "instance"

    tags = merge(local.tags, {
      Name = "custom-aim-node",
    })
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

module "eks_managed_node_group_with_standard_ami" {
  source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"

  create_iam_role = false
  iam_role_arn    = var.iam_role_arn_nodes

  name = "managed-eks-node-with-standard-ami"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_name              = var.cluster_name
  cluster_auth_base64       = module.eks.cluster_certificate_authority_data
  cluster_endpoint          = module.eks.cluster_endpoint
  cluster_service_ipv4_cidr = var.main_network_block

  ami_type       = "AL2_x86_64"
  instance_types = ["t3.small", "t2.small"]
  disk_size      = 20

  vpc_security_group_ids = [
    module.eks.cluster_primary_security_group_id,
    module.eks.cluster_security_group_id,
  ]

  # if you disable this the default container will be docker
  create_launch_template = true

  min_size     = 1
  max_size     = 1
  desired_size = 1

  post_bootstrap_user_data = ""
  pre_bootstrap_user_data  = <<-EOT
    #!/bin/bash
    set -ex
    cat <<-EOF > /etc/profile.d/bootstrap.sh
    export CONTAINER_RUNTIME="containerd"
    EOF
    # Source extra environment variables in bootstrap script
    sed -i '/^set -o errexit/a\\nsource /etc/profile.d/bootstrap.sh' /etc/eks/bootstrap.sh
  EOT

  # use the label setting to add labels to the node
  labels = {
    my-label-3 = "value-3"
    my-label-4 = "value-4"
  }

  tags = local.tags
}

