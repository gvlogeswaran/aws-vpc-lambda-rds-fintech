# ============================================================
# main.tf — Terraform & Provider Configuration
# Project: aws-vpc-lambda-rds-fintech
# ============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # AWS provider — manages all AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Archive provider — packages Lambda function code into .zip
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# --------------------------
# AWS Provider Configuration
# --------------------------
provider "aws" {
  region = var.aws_region

  # Apply common_tags to ALL supported resources automatically.
  # Individual resources can override or extend tags as needed.
  default_tags {
    tags = local.common_tags
  }
}

# --------------------------
# Archive Provider
# (No configuration needed — used implicitly by lambda.tf)
# --------------------------
provider "archive" {}
