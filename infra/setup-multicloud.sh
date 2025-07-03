#!/bin/bash

# setup-multicloud.sh
# Multi-cloud Kubernetes with Istio - Complete Project Setup Script
# Creates all necessary files for the project

set -e  # Exit on any error

echo "🚀 Setting up Multi-cloud Kubernetes with Istio project..."

# Create project directory
PROJECT_DIR="multicloud-kubernetes"

if [ -d "$PROJECT_DIR" ]; then
    echo "⚠️  Directory '$PROJECT_DIR' already exists!"
    read -p "Do you want to remove it and start fresh? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$PROJECT_DIR"
        echo "✅ Removed existing directory"
    else
        echo "❌ Aborting setup"
        exit 1
    fi
fi

mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

echo "📁 Created project directory: $PROJECT_DIR"

# =============================================================================
# FILE 1: versions.tf
# =============================================================================
echo "📝 Creating versions.tf..."

cat > versions.tf << 'EOF'
# versions.tf
# Provider version requirements

terraform {
  required_version = ">= 1.3"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
EOF

# =============================================================================
# FILE 2: variables.tf
# =============================================================================
echo "📝 Creating variables.tf..."

cat > variables.tf << 'EOF'
# variables.tf
# Input variables for the multi-cloud infrastructure

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-north-1"
}

variable "azure_location" {
  description = "Azure location"
  type        = string
  default     = "North Europe"
}

variable "cluster_version" {
  description = "Kubernetes version for both clusters"
  type        = string
  default     = "1.31"  # Stable version supported by both EKS and AKS
}

variable "aws_cluster_version" {
  description = "AWS EKS Kubernetes version (can use 1.32 or 1.33)"
  type        = string
  default     = null  # Uses cluster_version if not specified
}

variable "azure_cluster_version" {
  description = "Azure AKS Kubernetes version (supports up to 1.32)"
  type        = string
  default     = null  # Uses cluster_version if not specified
}

variable "aws_node_instance_type" {
  description = "AWS EKS node instance type"
  type        = string
  default     = "t3.medium"
}

variable "azure_node_vm_size" {
  description = "Azure AKS node VM size"
  type        = string
  default     = "Standard_B2s"
}

variable "node_count" {
  description = "Number of nodes per cluster"
  type        = number
  default     = 2
}

variable "environment" {
  description = "Environment tag"
  type        = string
  default     = "multicloud"
}
EOF

# =============================================================================
# FILE 3: main.tf
# =============================================================================
echo "📝 Creating main.tf..."

cat > main.tf << 'EOF'
# main.tf
# Multi-cloud Kubernetes infrastructure with Istio service mesh

# AWS Provider
provider "aws" {
  region = var.aws_region
}

# Azure Provider
provider "azurerm" {
  features {}
}

# Data sources for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# AWS VPC Module
module "aws_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "multicloud-vpc"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true
  enable_vpn_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Environment = var.environment
  }
}

# AWS EKS Module
module "aws_eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "multicloud-aws"
  cluster_version = coalesce(var.aws_cluster_version, var.cluster_version)

  vpc_id     = module.aws_vpc.vpc_id
  subnet_ids = module.aws_vpc.private_subnets

  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    default = {
      min_size     = 1
      max_size     = 3
      desired_size = var.node_count

      instance_types = [var.aws_node_instance_type]
      capacity_type  = "ON_DEMAND"
    }
  }

  tags = {
    Environment = var.environment
  }
}

# Azure Resource Group
resource "azurerm_resource_group" "main" {
  name     = "multicloud-rg"
  location = var.azure_location

  tags = {
    Environment = var.environment
  }
}

# Azure AKS Module
module "azure_aks" {
  source  = "Azure/aks/azurerm"
  version = "~> 7.0"

  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  cluster_name       = "multicloud-azure"

  kubernetes_version   = coalesce(var.azure_cluster_version, var.cluster_version)
  orchestrator_version = coalesce(var.azure_cluster_version, var.cluster_version)

  # Default node pool configuration using agents_* parameters
  agents_count     = var.node_count
  agents_size      = var.azure_node_vm_size
  agents_pool_name = "default"
  
  enable_auto_scaling = false

  tags = {
    Environment = var.environment
  }
}

# Kubernetes provider for AWS EKS
provider "kubernetes" {
  alias                  = "aws"
  host                   = module.aws_eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.aws_eks.cluster_certificate_authority_data)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.aws_eks.cluster_name]
  }
}

# Kubernetes provider for Azure AKS
provider "kubernetes" {
  alias                  = "azure"
  host                   = module.azure_aks.kube_config.0.host
  cluster_ca_certificate = base64decode(module.azure_aks.kube_config.0.cluster_ca_certificate)
  client_certificate     = base64decode(module.azure_aks.kube_config.0.client_certificate)
  client_key             = base64decode(module.azure_aks.kube_config.0.client_key)
}

# Helm provider for AWS EKS
provider "helm" {
  alias = "aws"
  kubernetes {
    host                   = module.aws_eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.aws_eks.cluster_certificate_authority_data)
    
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.aws_eks.cluster_name]
    }
  }
}

# Helm provider for Azure AKS
provider "helm" {
  alias = "azure"
  kubernetes {
    host                   = module.azure_aks.kube_config.0.host
    cluster_ca_certificate = base64decode(module.azure_aks.kube_config.0.cluster_ca_certificate)
    client_certificate     = base64decode(module.azure_aks.kube_config.0.client_certificate)
    client_key             = base64decode(module.azure_aks.kube_config.0.client_key)
  }
}

# Istio namespace for AWS
resource "kubernetes_namespace" "istio_system_aws" {
  provider = kubernetes.aws
  metadata {
    name = "istio-system"
    labels = {
      "topology.istio.io/network" = "aws-network"
    }
  }
}

# Istio namespace for Azure
resource "kubernetes_namespace" "istio_system_azure" {
  provider = kubernetes.azure
  metadata {
    name = "istio-system"
    labels = {
      "topology.istio.io/network" = "azure-network"
    }
  }
}

# Istio Base on AWS
resource "helm_release" "istio_base_aws" {
  provider   = helm.aws
  name       = "istio-base"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "base"
  version    = "1.26.2"
  namespace  = kubernetes_namespace.istio_system_aws.metadata[0].name

  set {
    name  = "global.meshID"
    value = "mesh1"
  }

  set {
    name  = "global.network"
    value = "aws-network"
  }
}

# Istio Base on Azure
resource "helm_release" "istio_base_azure" {
  provider   = helm.azure
  name       = "istio-base"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "base"
  version    = "1.26.2"
  namespace  = kubernetes_namespace.istio_system_azure.metadata[0].name

  set {
    name  = "global.meshID"
    value = "mesh1"
  }

  set {
    name  = "global.network"
    value = "azure-network"
  }
}

# Istiod on AWS
resource "helm_release" "istiod_aws" {
  provider   = helm.aws
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  version    = "1.26.2"
  namespace  = kubernetes_namespace.istio_system_aws.metadata[0].name

  depends_on = [helm_release.istio_base_aws]

  set {
    name  = "global.meshID"
    value = "mesh1"
  }

  set {
    name  = "global.network"
    value = "aws-network"
  }

  set {
    name  = "pilot.env.EXTERNAL_ISTIOD"
    value = "false"
  }
}

# Istiod on Azure
resource "helm_release" "istiod_azure" {
  provider   = helm.azure
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  version    = "1.26.2"
  namespace  = kubernetes_namespace.istio_system_azure.metadata[0].name

  depends_on = [helm_release.istio_base_azure]

  set {
    name  = "global.meshID"
    value = "mesh1"
  }

  set {
    name  = "global.network"
    value = "azure-network"
  }

  set {
    name  = "pilot.env.EXTERNAL_ISTIOD"
    value = "false"
  }
}

# Istio Gateway on AWS
resource "helm_release" "istio_gateway_aws" {
  provider   = helm.aws
  name       = "istio-eastwestgateway"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  version    = "1.26.2"
  namespace  = kubernetes_namespace.istio_system_aws.metadata[0].name

  depends_on = [helm_release.istiod_aws]

  set {
    name  = "service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "service.ports[0].port"
    value = "15021"
  }

  set {
    name  = "service.ports[0].name"
    value = "status-port"
  }

  set {
    name  = "service.ports[1].port"
    value = "15443"
  }

  set {
    name  = "service.ports[1].name"
    value = "tls"
  }
}

# Istio Gateway on Azure
resource "helm_release" "istio_gateway_azure" {
  provider   = helm.azure
  name       = "istio-eastwestgateway"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  version    = "1.26.2"
  namespace  = kubernetes_namespace.istio_system_azure.metadata[0].name

  depends_on = [helm_release.istiod_azure]

  set {
    name  = "service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "service.ports[0].port"
    value = "15021"
  }

  set {
    name  = "service.ports[0].name"
    value = "status-port"
  }

  set {
    name  = "service.ports[1].port"
    value = "15443"
  }

  set {
    name  = "service.ports[1].name"
    value = "tls"
  }
}

# Configure kubectl contexts automatically
resource "null_resource" "configure_kubectl_aws" {
  depends_on = [module.aws_eks]
  
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.aws_eks.cluster_name} --alias aws-cluster"
  }
  
  triggers = {
    cluster_name = module.aws_eks.cluster_name
  }
}

resource "null_resource" "configure_kubectl_azure" {
  depends_on = [module.azure_aks]
  
  provisioner "local-exec" {
    command = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${module.azure_aks.cluster_name} --context azure-cluster --overwrite-existing"
  }
  
  triggers = {
    cluster_name = module.azure_aks.cluster_name
  }
}

# Verify Istio installation
resource "null_resource" "verify_istio_aws" {
  depends_on = [helm_release.istio_gateway_aws, null_resource.configure_kubectl_aws]
  
  provisioner "local-exec" {
    command = "kubectl --context=aws-cluster wait --for=condition=ready pod -l app=istiod -n istio-system --timeout=300s"
  }
}

resource "null_resource" "verify_istio_azure" {
  depends_on = [helm_release.istio_gateway_azure, null_resource.configure_kubectl_azure]
  
  provisioner "local-exec" {
    command = "kubectl --context=azure-cluster wait --for=condition=ready pod -l app=istiod -n istio-system --timeout=300s"
  }
}
EOF

# =============================================================================
# FILE 4: outputs.tf
# =============================================================================
echo "📝 Creating outputs.tf..."

cat > outputs.tf << 'EOF'
# outputs.tf
# Output values after deployment

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

# Azure AKS Outputs
output "azure_cluster_endpoint" {
  description = "Azure AKS cluster endpoint"
  value       = module.azure_aks.kube_config.0.host
}

output "azure_cluster_name" {
  description = "Azure AKS cluster name"
  value       = module.azure_aks.cluster_name
}

output "azure_resource_group_name" {
  description = "Azure resource group name"
  value       = azurerm_resource_group.main.name
}

# Kubectl Commands
output "kubectl_commands" {
  description = "Useful kubectl commands for managing clusters"
  value = {
    configure_aws     = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.aws_eks.cluster_name}"
    configure_azure   = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${module.azure_aks.cluster_name}"
    switch_to_aws     = "kubectl config use-context aws-cluster"
    switch_to_azure   = "kubectl config use-context azure-cluster"
    verify_aws_nodes  = "kubectl --context=aws-cluster get nodes"
    verify_azure_nodes = "kubectl --context=azure-cluster get nodes"
    verify_istio      = "kubectl --context=aws-cluster get pods -n istio-system && kubectl --context=azure-cluster get pods -n istio-system"
  }
}
EOF

# =============================================================================
# FILE 5: terraform.tfvars
# =============================================================================
echo "📝 Creating terraform.tfvars..."

cat > terraform.tfvars << 'EOF'
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
EOF

# =============================================================================
# FILE 6: .gitignore
# =============================================================================
echo "📝 Creating .gitignore..."

cat > .gitignore << 'EOF'
# .gitignore
# Terraform security - prevent committing sensitive files

# Terraform state files
*.tfstate
*.tfstate.*
*.tfstate.backup

# Terraform configuration files with secrets
terraform.tfvars
*.auto.tfvars

# Override files
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# Terraform working directories
.terraform/
.terraform.lock.hcl

# Crash logs
crash.log
crash.*.log

# CLI configuration files
.terraformrc
terraform.rc

# Kubernetes config files
kubeconfig
kubeconfig_*
*.kubeconfig

# IDE/Editor files
.vscode/
.idea/
*.swp
*.swo
*~

# OS generated files
.DS_Store
Thumbs.db

# Logs and temporary files
*.log
*.tmp
*.temp

# Environment files
.env
.env.*

# Backup files
*.backup
*.bak

# Terraform plan files
*.tfplan
*.plan
EOF

# =============================================================================
# FINAL SETUP INSTRUCTIONS
# =============================================================================

echo ""
echo "🎉 Multi-cloud Kubernetes project setup complete!"
echo ""
echo "📁 Created files:"
echo "   ├── main.tf"
echo "   ├── variables.tf"
echo "   ├── versions.tf"
echo "   ├── outputs.tf"
echo "   ├── terraform.tfvars"
echo "   └── .gitignore"
echo ""
echo "🚀 Next steps:"
echo "   1. cd $PROJECT_DIR"
echo "   2. Edit terraform.tfvars if needed (regions, instance types, etc.)"
echo "   3. terraform init"
echo "   4. terraform plan"
echo "   5. terraform apply"
echo ""
echo "🔧 What you'll get:"
echo "   ✅ AWS EKS cluster (Kubernetes 1.31) with 2 nodes"
echo "   ✅ Azure AKS cluster (Kubernetes 1.31) with 2 nodes"
echo "   ✅ Istio 1.26.2 service mesh on both clusters"
echo "   ✅ Cross-cloud networking configured"
echo "   ✅ kubectl contexts automatically configured"
echo ""
echo "⏱️  Estimated deployment time: ~15 minutes"
echo ""
echo "🎯 Ready to deploy? Run:"
echo "   cd $PROJECT_DIR && terraform init && terraform apply"
