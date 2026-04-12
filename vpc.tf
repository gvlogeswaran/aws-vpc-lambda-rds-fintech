# ============================================================
# vpc.tf — VPC, Subnets, Gateways & Routing
# Project: aws-vpc-lambda-rds-fintech
# ============================================================

# --------------------------
# VPC
# --------------------------
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # Required for RDS and internal DNS to resolve hostnames
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# --------------------------
# Internet Gateway (IGW)
# Allows public subnets to reach the internet
# --------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ============================================================
# PUBLIC SUBNETS  (2 × AZ)
# Hosts: NAT Gateway, load balancers (if any)
# ============================================================
resource "aws_subnet" "public" {
  count = 2

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]

  # Carve /24 slices from the VPC CIDR:
  #  index 0 → 10.0.0.0/24
  #  index 1 → 10.0.1.0/24
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index)

  # Instances launched here receive a public IP automatically
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-${count.index + 1}"
    Tier = "Public"
  }
}

# ============================================================
# PRIVATE APP SUBNETS  (2 × AZ)
# Hosts: Lambda functions — no direct internet exposure
# ============================================================
resource "aws_subnet" "private_app" {
  count = 2

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]

  #  index 0 → 10.0.10.0/24
  #  index 1 → 10.0.11.0/24
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index + 10)

  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-private-app-subnet-${count.index + 1}"
    Tier = "PrivateApp"
  }
}

# ============================================================
# PRIVATE DB SUBNETS  (2 × AZ)
# Hosts: RDS PostgreSQL — no internet access whatsoever
# ============================================================
resource "aws_subnet" "private_db" {
  count = 2

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]

  #  index 0 → 10.0.20.0/24
  #  index 1 → 10.0.21.0/24
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index + 20)

  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-private-db-subnet-${count.index + 1}"
    Tier = "PrivateDB"
  }
}

# ============================================================
# NAT GATEWAY  (Single AZ — cost-optimised for non-prod)
# Allows private subnets outbound internet (HTTPS, package installs)
# ============================================================

# Elastic IP for NAT Gateway — must be in us-east-1 or explicit domain
resource "aws_eip" "nat" {
  domain = "vpc"

  # Ensure the IGW exists before the EIP so there is a route for traffic
  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

# NAT Gateway placed in the FIRST public subnet
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${var.project_name}-nat-gw"
  }
}

# ============================================================
# ROUTE TABLES
# ============================================================

# --- Public route table: send 0.0.0.0/0 → IGW ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# --- Private route table: send 0.0.0.0/0 → NAT GW ---
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

# ============================================================
# ROUTE TABLE ASSOCIATIONS
# ============================================================

# Public subnets → public route table
resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private app subnets (Lambda) → private route table
resource "aws_route_table_association" "private_app" {
  count = 2

  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private.id
}

# Private DB subnets (RDS) → private route table
# RDS only needs outbound for minor patch downloads; NAT covers that.
resource "aws_route_table_association" "private_db" {
  count = 2

  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private.id
}
