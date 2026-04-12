# ============================================================
# lambda.tf — Lambda Function, IAM Role & CloudWatch Logs
# Project: aws-vpc-lambda-rds-fintech
# ============================================================

# --------------------------
# Package Lambda source code into a .zip archive
# Terraform tracks the hash; if function.py changes, it re-deploys.
# --------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/function.py"
  output_path = "${path.module}/lambda/function.zip"
}

# ============================================================
# IAM — Lambda Execution Role
# ============================================================
resource "aws_iam_role" "lambda_exec" {
  name        = "${var.project_name}-lambda-exec-role"
  description = "Execution role for the fintech market-data Lambda function"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaAssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-lambda-exec-role"
  }
}

# Attach AWS managed policy — grants ENI creation/deletion needed for VPC Lambda
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# ============================================================
# Lambda Function
# ============================================================
resource "aws_lambda_function" "market_data" {
  function_name = "${var.project_name}-market-data"
  description   = "Inserts and queries market data in RDS PostgreSQL"

  # ---- Runtime ----
  runtime = "python3.12"
  handler = "function.lambda_handler"

  # ---- Deployment Package ----
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # ---- Execution Role ----
  role = aws_iam_role.lambda_exec.arn

  # ---- Performance ----
  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory_size

  # ---- VPC Configuration ----
  # Lambda ENIs will be placed in private_app subnets so they can
  # reach RDS but are NOT directly reachable from the internet.
  vpc_config {
    subnet_ids         = aws_subnet.private_app[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  # ---- Layers ----
  # Klayers-managed psycopg2-binary for Python 3.12 in me-south-1

  layers = [
    "arn:aws:lambda:us-east-1:770693421928:layer:Klayers-p312-psycopg2-binary:1"
  ]

  # ---- Environment Variables ----
  # Credentials are passed via env vars; consider AWS Secrets Manager for prod.
  environment {
    variables = {
      DB_HOST     = aws_db_instance.postgres.address
      DB_PORT     = tostring(aws_db_instance.postgres.port)
      DB_NAME     = var.db_name
      DB_USER     = var.db_username
      DB_PASSWORD = var.db_password
    }
  }

  # ---- Logging ----
  # Direct Lambda logs to the CloudWatch group defined below
  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.lambda.name
  }

  tags = {
    Name = "${var.project_name}-market-data"
    Role = "Lambda"
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_vpc_access,
    aws_cloudwatch_log_group.lambda,
    aws_db_instance.postgres,
  ]
}

# ============================================================
# CloudWatch Log Group
# Retaining only 7 days of logs to keep costs low in dev.
# ============================================================
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.project_name}-market-data"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-lambda-logs"
    Role = "Observability"
  }
}
