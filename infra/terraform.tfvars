# terraform.tfvars
# Your actual configuration values

# Cloud regions
aws_region     = "eu-north-1"
azure_location = "North Europe"

# Kubernetes versions
cluster_version = "1.31"

# Optional: Use different versions per cloud
# aws_cluster_version   = "1.32"
# azure_cluster_version = "1.31"

# Node configuration
aws_node_instance_type = "t3.medium"
azure_node_vm_size     = "Standard_B2s"
node_count            = 2

# Environment
environment = "multicloud"
