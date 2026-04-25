#!/bin/bash

# ---------------------------------------------------------
# Setup: Docker & System Deps
# ---------------------------------------------------------

# update packages and grab docker
dnf update -y
dnf install -y docker
dnf install -y nmap-ncat
dnf install -y mariadb105
systemctl start docker
systemctl enable docker

# let ec2-user run docker commands without sudo
usermod -a -G docker ec2-user

# ---------------------------------------------------------
# Docker Compose (Latest binary)
# ---------------------------------------------------------
DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
mkdir -p $DOCKER_CONFIG/cli-plugins
curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# ---------------------------------------------------------
# EBS Volume Mount (Data Persistence)
# ---------------------------------------------------------
# t3 instances usually map the secondary EBS to nvme1n1. finding it dynamically:
DEVICE="/dev/$(lsblk -no NAME | grep -v "nvme0n1" | grep "nvme" | head -n 1)"
MOUNT_POINT="/var/lib/elasticsearch_data"

if [ -n "$DEVICE" ]; then
    # format only if it's raw/empty
    if [ -z "$(lsblk -fno FSTYPE $DEVICE)" ]; then
        sudo mkfs -t xfs $DEVICE
    fi
    
    # mount it
    sudo mkdir -p $MOUNT_POINT
    sudo mount $DEVICE $MOUNT_POINT
    
    # add to fstab so it survives reboots
    echo "$DEVICE $MOUNT_POINT xfs defaults,nofail 0 2" | sudo tee -a /etc/fstab
    
    # elasticsearch container runs as uid 1000, needs ownership of this folder
    sudo chown -R 1000:1000 $MOUNT_POINT
else
    # fallback in case ebs detection fails
    sudo mkdir -p $MOUNT_POINT
    sudo chown -R 1000:1000 $MOUNT_POINT
fi

# ---------------------------------------------------------
# Workspace & ELK Config
# ---------------------------------------------------------
mkdir -p /home/ec2-user/monitoring
cd /home/ec2-user/monitoring

# Note: Security (xpack) disabled for PoC speed. 
# Heap limited to 1GB to prevent OOM in t3.medium instances.
cat <<EOF > docker-compose.yml
version: '3.8'

services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.12.0
    container_name: elasticsearch
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
      - "ES_JAVA_OPTS=-Xms1g -Xmx1g"
    ulimits:
      memlock:
        soft: -1
        hard: -1
    ports:
      - 9200:9200
    volumes:
      - $MOUNT_POINT:/usr/share/elasticsearch/data
    networks:
      - elk-network

  kibana:
    image: docker.elastic.co/kibana/kibana:8.12.0
    container_name: kibana
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
    ports:
      - 5601:5601
    depends_on:
      - elasticsearch
    networks:
      - elk-network

networks:
  elk-network:
    driver: bridge
EOF

# fix perms for the monitoring folder
chown -R ec2-user:ec2-user /home/ec2-user/monitoring

# ---------------------------------------------------------
# Run
# ---------------------------------------------------------

# using sudo here because the docker group change requires a re-login to take effect
sudo /usr/local/bin/docker-compose up -d

# ---------------------------------------------------------
# Get Elastic Agent (matching ELK version)
# ---------------------------------------------------------
cd /home/ec2-user
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-8.12.0-linux-x86_64.tar.gz
tar xzvf elastic-agent-8.12.0-linux-x86_64.tar.gz
chown -R ec2-user:ec2-user /home/ec2-user/elastic-agent-8.12.0-linux-x86_64

echo "Wait 2-3 mins for Elastic to be healthy at :5601"