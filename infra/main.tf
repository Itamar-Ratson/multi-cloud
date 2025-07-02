terraform {
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
  }
}

# AWS Provider
provider "aws" {
  region = "eu-north-1"
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

  enable_nat_gateway = true
  enable_vpn_gateway = false
  enable_dns_hostnames = true
  enable_dns_support = true

  tags = {
    Environment = "multicloud"
  }
}

# AWS EKS Module
module "aws_eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = "multicloud-aws"
  cluster_version = "1.27"

  vpc_id     = module.aws_vpc.vpc_id
  subnet_ids = module.aws_vpc.private_subnets

  manage_aws_auth_configmap = true

  eks_managed_node_groups = {
    default = {
      min_size     = 1
      max_size     = 3
      desired_size = 2

      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
    }
  }

  tags = {
    Environment = "multicloud"
  }
}

# Azure Resource Group
resource "azurerm_resource_group" "main" {
  name     = "multicloud-rg"
  location = "North Europe"

  tags = {
    Environment = "multicloud"
  }
}

# Azure AKS Module
module "azure_aks" {
  source  = "Azure/aks/azurerm"
  version = "~> 7.0"

  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  cluster_name       = "multicloud-azure"

  kubernetes_version = "1.27"
  orchestrator_version = "1.27"

  default_node_pool = {
    name                = "default"
    node_count          = 2
    vm_size            = "Standard_B2s"
    enable_auto_scaling = false
  }

  tags = {
    Environment = "multicloud"
  }
}

# Kubernetes provider for AWS EKS
provider "kubernetes" {
  alias = "aws"
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
  alias = "azure"
  host                   = module.azure_aks.kube_config.0.host
  cluster_ca_certificate = base64decode(module.azure_aks.kube_config.0.cluster_ca_certificate)
  client_certificate     = base64decode(module.azure_aks.kube_config.0.client_certificate)
  client_key            = base64decode(module.azure_aks.kube_config.0.client_key)
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
    client_key            = base64decode(module.azure_aks.kube_config.0.client_key)
  }
}

# Istio namespace for AWS
resource "kubernetes_namespace" "istio_system_aws" {
  provider = kubernetes.aws
  metadata {
    name = "istio-system"
    labels = {
      topology.istio.io/network = "aws-network"
    }
  }
}

# Istio namespace for Azure
resource "kubernetes_namespace" "istio_system_azure" {
  provider = kubernetes.azure
  metadata {
    name = "istio-system"
    labels = {
      topology.istio.io/network = "azure-network"
    }
  }
}

# Istio Base on AWS
resource "helm_release" "istio_base_aws" {
  provider   = helm.aws
  name       = "istio-base"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "base"
  version    = "1.19.0"
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
  version    = "1.19.0"
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
  version    = "1.19.0"
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
  version    = "1.19.0"
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
  version    = "1.19.0"
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
  version    = "1.19.0"
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

# Outputs
output "aws_cluster_endpoint" {
  value = module.aws_eks.cluster_endpoint
}

output "aws_cluster_name" {
  value = module.aws_eks.cluster_name
}

output "azure_cluster_endpoint" {
  value = module.azure_aks.kube_config.0.host
}

output "azure_cluster_name" {
  value = module.azure_aks.cluster_name
}

output "kubectl_commands" {
  value = {
    aws_context   = "kubectl config use-context aws-cluster"
    azure_context = "kubectl config use-context azure-cluster"
    verify_istio  = "kubectl --context=aws-cluster get pods -n istio-system && kubectl --context=azure-cluster get pods -n istio-system"
  }
}
