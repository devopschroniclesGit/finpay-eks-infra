# ── VPC ───────────────────────────────────────────────────────────────────────

resource "aws_vpc" "finpay" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name                                              = "${var.app_name}-vpc"
    "kubernetes.io/cluster/${var.app_name}-eks"       = "shared"
  }
}

# ── Internet Gateway ──────────────────────────────────────────────────────────

resource "aws_internet_gateway" "finpay" {
  vpc_id = aws_vpc.finpay.id
  tags   = { Name = "${var.app_name}-igw" }
}

# ── Public subnets (ALB lives here) ──────────────────────────────────────────

resource "aws_subnet" "public" {
  count                   = 3
  vpc_id                  = aws_vpc.finpay.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                              = "${var.app_name}-public-${var.availability_zones[count.index]}"
    "kubernetes.io/cluster/${var.app_name}-eks"       = "shared"
    "kubernetes.io/role/elb"                          = "1"   # ALB controller tag
  }
}

# ── Private subnets (EKS nodes live here) ────────────────────────────────────

resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = aws_vpc.finpay.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name                                              = "${var.app_name}-private-${var.availability_zones[count.index]}"
    "kubernetes.io/cluster/${var.app_name}-eks"       = "shared"
    "kubernetes.io/role/internal-elb"                 = "1"
  }
}

# ── Data subnets (RDS + ElastiCache — no route to internet) ──────────────────

resource "aws_subnet" "data" {
  count             = 3
  vpc_id            = aws_vpc.finpay.id
  cidr_block        = "10.0.${count.index + 20}.0/24"
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.app_name}-data-${var.availability_zones[count.index]}"
  }
}

# ── NAT Gateway (one per VPC — cost-optimised for demo) ───────────────────────

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.app_name}-nat-eip" }
}

resource "aws_nat_gateway" "finpay" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id   # NAT lives in first public subnet
  tags          = { Name = "${var.app_name}-nat" }
  depends_on    = [aws_internet_gateway.finpay]
}

# ── Route tables ──────────────────────────────────────────────────────────────

# Public: route to IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.finpay.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.finpay.id
  }
  tags = { Name = "${var.app_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private: route to NAT
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.finpay.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.finpay.id
  }
  tags = { Name = "${var.app_name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Data: no internet route — isolated
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.finpay.id
  tags   = { Name = "${var.app_name}-data-rt" }
}

resource "aws_route_table_association" "data" {
  count          = 3
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}
