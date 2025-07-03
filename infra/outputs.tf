# outputs.tf
# Output values after deployment
# FIXED: Correct Azure AKS module output attributes

# AWS EKS Outputs
output "aws_cluster_endpoint" {
  description = "AWS EKS cluster endpoint"
  value       = module.aws_eks.cluster_endpoint
}

output "aws_cluster_name" {
  description = "AWS EKS cluster name"
  value       = module.aws_eks.cluster_name
}

output "aws_cluster_version" {
  description = "AWS EKS cluster Kubernetes version"
  value       = module.aws_eks.cluster_version
}

# Azure AKS Outputs - FIXED
output "azure_cluster_endpoint" {
  description = "Azure AKS cluster endpoint"
  value       = module.azure_aks.host
}

output "azure_cluster_name" {
  description = "Azure AKS cluster name"
  value       = module.azure_aks.aks_name
}

output "azure_resource_group_name" {
  description = "Azure resource group name"
  value       = azurerm_resource_group.main.name
}

# Kubectl Commands - FIXED
output "kubectl_commands" {
  description = "Useful kubectl commands for managing clusters"
  value = {
    configure_aws     = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.aws_eks.cluster_name}"
    configure_azure   = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${module.azure_aks.aks_name}"
    switch_to_aws     = "kubectl config use-context aws-cluster"
    switch_to_azure   = "kubectl config use-context azure-cluster"
    verify_aws_nodes  = "kubectl --context=aws-cluster get nodes"
    verify_azure_nodes = "kubectl --context=azure-cluster get nodes"
    verify_istio      = "kubectl --context=aws-cluster get pods -n istio-system && kubectl --context=azure-cluster get pods -n istio-system"
  }
}
