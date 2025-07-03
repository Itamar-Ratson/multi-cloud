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
