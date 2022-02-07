Terraform EKS demo
===

In the main.tf file there are two examples:
- nodes using the custom AMI (module.eks_managed_node_group_with_standard_ami), 
- nodes using the custom AMI provided by AWS (module.eks_managed_node_group_with_standard_ami).

This example is an attempt of validating two main things:
- adding labels to the eks nodes
- initializing the containerd as the main runtime container

Be aware that this is only a demo to test the [terraform aws modules](https://github.com/terraform-aws-modules/terraform-aws-eks).

You can check the needed variables in the terraform.tfvars.example.
