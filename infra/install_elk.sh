#!/bin/bash

# ---------------------------------------------------------
# Setup: Docker & System Deps
# ---------------------------------------------------------

# Update and get Docker engine
dnf update -y
dnf install -y docker
systemctl start docker
systemctl enable docker

# Fix perms: allow ec2-user to run docker without sudo
usermod -a -G docker ec2-user

# ---------------------------------------------------------
# Docker Compose (Latest binary)
# ---------------------------------------------------------
DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
mkdir -p $DOCKER_CONFIG/cli-plugins
curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

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

# Ensure perms for ec2-user
chown -R ec2-user:ec2-user /home/ec2-user/monitoring

# ---------------------------------------------------------
# Run
# ---------------------------------------------------------

# Using sudo here because group changes require logout/login to take effect
sudo /usr/local/bin/docker-compose up -d

echo "Wait 2-3 mins for Elastic to be healthy at :5601"