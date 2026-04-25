
# RDS subnet group (needs at least 2 azs)
resource "aws_db_subnet_group" "rds_monitoring_group" {
  name       = "rds-monitoring-subnet-group"
  subnet_ids = [aws_subnet.public_subnet_1a.id, aws_subnet.public_subnet_1b.id]

  tags = {
    Name = "rds-monitoring-subnet-group"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "rds-mysql-security-group"
  description = "Allow MySQL traffic from EC2 monitoring server"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    # only the EC2 Security Group can enter
    security_groups = [aws_security_group.elk_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-rds-mysql"
  }
}

resource "aws_db_instance" "mysql_db" {
  identifier           = "monitoring-db-mysql"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro" 
  allocated_storage    = 20
  storage_type         = "gp2"

  db_name              = "projectdb"
  username             = var.db_user
  password             = var.db_pass

  db_subnet_group_name   = aws_db_subnet_group.rds_monitoring_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  
  # Best practices for dev/PoC
  publicly_accessible  = false
  skip_final_snapshot  = true
  multi_az             = false

  tags = {
    Name = "rds-monitoring-instance"
  }
}

