# ============================================================
# rds.tf — RDS PostgreSQL 15.4 Instance
# Project: aws-vpc-lambda-rds-fintech
# ============================================================

# --------------------------
# DB Subnet Group
# RDS requires a subnet group covering at least 2 AZs in the VPC.
# We use both private DB subnets for HA placement.
# --------------------------
resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-db-subnet-group"
  description = "DB subnet group spanning both private DB subnets"
  subnet_ids  = aws_subnet.private_db[*].id

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# --------------------------
# RDS PostgreSQL Instance
# --------------------------
resource "aws_db_instance" "postgres" {
  # ---- Identity ----
  identifier = "${var.project_name}-postgres"

  # ---- Engine ----
  engine         = "postgres"
  engine_version = "15"

  # ---- Instance Size ----
  instance_class = "db.t3.micro"

  # ---- Storage ----
  allocated_storage     = 20  # GB
  max_allocated_storage = 100 # Enable autoscaling up to 100 GB
  storage_type          = "gp2"
  storage_encrypted     = true # Encryption at rest (KMS default key)

  # ---- Database ----
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 5432

  # ---- Network ----
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false # Never expose RDS to the public internet

  # ---- Backup & Maintenance ----
  backup_retention_period = 0     # 0 = disable automated backups (dev environment)
  skip_final_snapshot     = true  # Do NOT create a final snapshot on destroy
  deletion_protection     = false # Allow terraform destroy in dev

  # ---- Monitoring & Logging ----
  # Export PostgreSQL logs to CloudWatch Logs
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Performance Insights — free tier: 7 days retention
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  # Enhanced Monitoring — 60 second granularity
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  # ---- Multi-AZ ----
  multi_az = false # Single-AZ for dev; set to true in prod

  # ---- Auto Minor Version Upgrades ----
  auto_minor_version_upgrade = true

  tags = {
    Name = "${var.project_name}-postgres"
    Role = "Database"
  }

  depends_on = [aws_db_subnet_group.main]
}

# ============================================================
# IAM Role for RDS Enhanced Monitoring
# Amazon requires a dedicated role to ship monitoring data to CloudWatch.
# ============================================================
resource "aws_iam_role" "rds_monitoring" {
  name        = "${var.project_name}-rds-monitoring-role"
  description = "Allows RDS to publish enhanced monitoring metrics to CloudWatch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RDSMonitoringAssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-rds-monitoring-role"
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
