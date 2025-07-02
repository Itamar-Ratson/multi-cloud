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
  description = "Kubernetes version"
  type        = string
  default     = "1.27"
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
