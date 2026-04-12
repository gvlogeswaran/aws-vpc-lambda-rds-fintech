# ============================================================
# security_groups.tf — Least-Privilege Security Groups
# Project: aws-vpc-lambda-rds-fintech
# ============================================================

# ============================================================
# LAMBDA SECURITY GROUP
# Allows Lambda functions to:
#   - Connect to RDS on 5432 (PostgreSQL)
#   - Reach the internet on 443 (HTTPS — AWS SDK, Klayers CDN)
#   - Reach the internet on 80  (HTTP  — package mirrors fallback)
# No inbound rules are needed (Lambda is invoked by AWS, not by peers).
# ============================================================
resource "aws_security_group" "lambda" {
  name        = "${var.project_name}-lambda-sg"
  description = "Security group for Lambda functions - egress to RDS and internet only"
  vpc_id      = aws_vpc.main.id

  # Rule 2 — HTTPS outbound (AWS SDK API calls, Secrets Manager, etc.)
  egress {
    description = "Allow HTTPS outbound for AWS SDK and external APIs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Rule 3 — HTTP outbound (fallback for package mirrors; can be removed in strict prod)
  egress {
    description = "Allow HTTP outbound (fallback)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-lambda-sg"
    Role = "Lambda"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================
# RDS SECURITY GROUP
# Ingress: ONLY from the Lambda security group on port 5432.
# No public access. Egress is left closed (RDS doesn't initiate).
# ============================================================
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for RDS PostgreSQL - ingress from Lambda SG only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-rds-sg"
    Role = "Database"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================
# STANDALONE SECURITY GROUP RULES
# Break circular dependencies between Lambda SG and RDS SG
# ============================================================
resource "aws_security_group_rule" "lambda_to_rds_egress" {
  type                     = "egress"
  security_group_id        = aws_security_group.lambda.id
  source_security_group_id = aws_security_group.rds.id
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  description              = "Allow Lambda to reach RDS PostgreSQL"
}

resource "aws_security_group_rule" "rds_from_lambda_ingress" {
  type                     = "ingress"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = aws_security_group.lambda.id
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  description              = "PostgreSQL from Lambda security group only"
}
