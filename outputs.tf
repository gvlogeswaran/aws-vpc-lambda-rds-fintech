# ============================================================
# outputs.tf — Terraform Output Values
# Project: aws-vpc-lambda-rds-fintech
# Run: terraform output  (after apply)
# ============================================================

# --------------------------
# VPC
# --------------------------
output "vpc_id" {
  description = "ID of the main VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block assigned to the VPC"
  value       = aws_vpc.main.cidr_block
}

# --------------------------
# Subnets
# --------------------------
output "public_subnet_ids" {
  description = "List of public subnet IDs (NAT GW, load balancers)"
  value       = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  description = "List of private app subnet IDs (Lambda functions)"
  value       = aws_subnet.private_app[*].id
}

output "private_db_subnet_ids" {
  description = "List of private DB subnet IDs (RDS PostgreSQL)"
  value       = aws_subnet.private_db[*].id
}

# --------------------------
# NAT Gateway
# --------------------------
output "nat_gateway_ip" {
  description = "Elastic IP address of the NAT Gateway (egress IP for private subnets)"
  value       = aws_eip.nat.public_ip
}

# --------------------------
# RDS
# --------------------------
output "rds_endpoint" {
  description = "Full RDS connection endpoint (host:port)"
  value       = aws_db_instance.postgres.endpoint
}

output "rds_address" {
  description = "Hostname portion of the RDS endpoint (without port)"
  value       = aws_db_instance.postgres.address
}

output "rds_port" {
  description = "Port the RDS instance listens on"
  value       = aws_db_instance.postgres.port
}

output "rds_database_name" {
  description = "Name of the database created inside PostgreSQL"
  value       = aws_db_instance.postgres.db_name
}

output "db_username" {
  description = "Master username for RDS (sensitive)"
  value       = aws_db_instance.postgres.username
  sensitive   = true
}

# --------------------------
# Lambda
# --------------------------
output "lambda_function_name" {
  description = "Name of the deployed Lambda function"
  value       = aws_lambda_function.market_data.function_name
}

output "lambda_function_arn" {
  description = "ARN of the deployed Lambda function"
  value       = aws_lambda_function.market_data.arn
}

output "lambda_invoke_arn" {
  description = "ARN used to invoke the Lambda function (e.g., via API Gateway)"
  value       = aws_lambda_function.market_data.invoke_arn
}

output "lambda_log_group" {
  description = "CloudWatch Log Group name for Lambda logs"
  value       = aws_cloudwatch_log_group.lambda.name
}

# --------------------------
# Security Groups
# --------------------------
output "lambda_security_group_id" {
  description = "ID of the Lambda security group"
  value       = aws_security_group.lambda.id
}

output "rds_security_group_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds.id
}
