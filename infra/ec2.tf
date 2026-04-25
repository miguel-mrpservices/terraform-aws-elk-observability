resource "aws_instance" "monitoring_server" {
  ami           = "ami-0de6934e87badb694"
  instance_type = "t3.medium"

  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.elk_sg.id]
  associate_public_ip_address = true
  key_name                    = "ssh-keygen"


  user_data = file("install_elk.sh")

  root_block_device {
    volume_size = 8
  }

  tags = {
    Name = "ELK-Monitor-Server"
  }
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

  skip_destroy = true
}

