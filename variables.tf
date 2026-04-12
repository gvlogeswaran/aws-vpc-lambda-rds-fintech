# ============================================================
# variables.tf — Input Variables & Local Values
# Project: aws-vpc-lambda-rds-fintech
# ============================================================

# --------------------------
# Provider / Region
# --------------------------
variable "aws_region" {
  description = "AWS region to deploy all resources"
  type        = string
  default     = "us-east-1"
}

# --------------------------
# Project Meta
# --------------------------
variable "project_name" {
  description = "Short name for the project — used in all resource names and tags"
  type        = string
  default     = "aws-vpc-lambda-rds-fintech"
}

variable "environment" {
  description = "Deployment environment (dev | staging | prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

# --------------------------
# VPC Networking
# --------------------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC (e.g. 10.0.0.0/16)"
  type        = string
  default     = "10.0.0.0/16"
}

# --------------------------
# RDS — Database Credentials (sensitive)
# --------------------------
variable "db_username" {
  description = "Master username for the RDS PostgreSQL instance"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Master password for the RDS PostgreSQL instance (min 8 chars)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "db_password must be at least 8 characters long."
  }
}

variable "db_name" {
  description = "Name of the initial database to create inside PostgreSQL"
  type        = string
  default     = "fintechdb"
}

# --------------------------
# Lambda Configuration
# --------------------------
variable "lambda_timeout" {
  description = "Maximum execution time for the Lambda function (seconds)"
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "lambda_timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocated to the Lambda function (MB)"
  type        = number
  default     = 256

  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 3008], var.lambda_memory_size)
    error_message = "lambda_memory_size must be a valid Lambda memory value (128, 256, 512, 1024, 2048, 3008)."
  }
}

# ============================================================
# Locals — Computed / Derived Values
# ============================================================
locals {
  # Common tags applied to every taggable resource
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Region      = var.aws_region
  }

  # Availability Zones — using the first two AZs in the region
  azs = [
    "${var.aws_region}a",
    "${var.aws_region}b",
  ]
}
