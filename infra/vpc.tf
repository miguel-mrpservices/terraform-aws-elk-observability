resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "monitoring-vpc"
  }
}

##---------------------------------------------------##

resource "aws_subnet" "public_subnet_1a" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"

  map_public_ip_on_launch = true
  availability_zone       = "eu-central-1a"

  tags = {
    Name = "monitoring-public-subnet-1a"
  }
}

resource "aws_subnet" "public_subnet_1b" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"

  map_public_ip_on_launch = true
  availability_zone       = "eu-central-1b"

  tags = {
    Name = "monitoring-public-subnet-1b"
  }
}

##---------------------------------------------------##

resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "monitoring-igw"
  }
}

##-------------------------Route table linked to both subnets--------------------------##

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet_1a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_assoc2" {
  subnet_id      = aws_subnet.public_subnet_1b.id
  route_table_id = aws_route_table.public_rt.id
}
