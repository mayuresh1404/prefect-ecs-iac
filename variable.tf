variable "aws_region" {
  description = "AWS region to deploy resources"
  default     = "ap-south-1"
}

variable "prefect_api_key_secret_name" {
  description = "Name of the AWS Secrets Manager secret containing Prefect API key"
  default     = "prefect-api-key"
}

variable "prefect_account_id" {
  description = "Prefect Cloud Account ID"
}

variable "prefect_workspace_id" {
  description = "Prefect Cloud Workspace ID"
}

variable "prefect_account_url" {
  description = "Prefect Cloud Account URL"
}

variable "ecs_work_pool" {
  description = "Prefect work pool name"
  default     = "ecs-work-pool"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs"
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs"
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}
