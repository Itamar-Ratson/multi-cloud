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

# Azure AKS - Simple direct resource (no module)
resource "azurerm_kubernetes_cluster" "azure_aks" {
  name                = "multicloud-azure"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "multicloud-azure"
  kubernetes_version  = coalesce(var.azure_cluster_version, var.cluster_version)

  default_node_pool {
    name       = "default"
    node_count = var.node_count
    vm_size    = var.azure_node_vm_size
  }

  identity {
    type = "SystemAssigned"
  }

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

# Kubernetes provider for Azure AKS - FIXED
provider "kubernetes" {
  alias                  = "azure"
  host                   = azurerm_kubernetes_cluster.azure_aks.kube_config.0.host
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.azure_aks.kube_config.0.cluster_ca_certificate)
  client_certificate     = base64decode(azurerm_kubernetes_cluster.azure_aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.azure_aks.kube_config.0.client_key)
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

# Helm provider for Azure AKS - FIXED
provider "helm" {
  alias = "azure"
  kubernetes {
    host                   = azurerm_kubernetes_cluster.azure_aks.kube_config.0.host
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.azure_aks.kube_config.0.cluster_ca_certificate)
    client_certificate     = base64decode(azurerm_kubernetes_cluster.azure_aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.azure_aks.kube_config.0.client_key)
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

# Configure kubectl contexts automatically - FIXED
resource "null_resource" "configure_kubectl_azure" {
  depends_on = [azurerm_kubernetes_cluster.azure_aks]
  
  provisioner "local-exec" {
    command = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.azure_aks.name} --context azure-cluster --overwrite-existing"
  }
  
  triggers = {
    cluster_name = azurerm_kubernetes_cluster.azure_aks.name
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
