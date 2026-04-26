resource "aws_instance" "monitoring_server" {
  ami           = "ami-0de6934e87badb694"
  instance_type = "t3.medium"

  subnet_id                   = aws_subnet.public_subnet_1a.id
  vpc_security_group_ids      = [aws_security_group.elk_sg.id]
  associate_public_ip_address = true
  key_name                    = "ssh-keygen"


  user_data = templatefile("userdata.sh", {
    rds_endpoint = aws_db_instance.mysql_db.address
    db_user      = var.db_user
    db_pass      = var.db_pass
  })

  root_block_device {
    volume_size = 8
  }

  tags = {
    Name = "ELK-Monitor-Server"
  }

  depends_on = [aws_db_instance.mysql_db]
}


resource "aws_ebs_volume" "elastic_data" {
  availability_zone = aws_instance.monitoring_server.availability_zone
  size              = 20
  tags              = { Name = "ElasticData" }
}

resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.elastic_data.id
  instance_id = aws_instance.monitoring_server.id

}

##---------------------------------------------------##

resource "aws_security_group" "elk_sg" {
  name        = "elk-monitoring-sg"
  description = "Security group for ELK and SSH"
  vpc_id      = aws_vpc.main.id

  # kibana port
  ingress {
    from_port   = 5601
    to_port     = 5601
    protocol    = "tcp"
    cidr_blocks = ["${var.admin_ip}/32"]
  }

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.admin_ip}/32"]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

