#!/bin/bash

# ---------------------------------------------------------
# Setup: Docker & System Deps
# ---------------------------------------------------------

# Update packages and install required tools
dnf update -y
dnf install -y docker nmap-ncat mariadb105 wget
systemctl start docker
systemctl enable docker

# Let ec2-user run docker commands without sudo
usermod -a -G docker ec2-user

# ---------------------------------------------------------
# Docker Compose (Latest binary)
# ---------------------------------------------------------
DOCKER_CONFIG=$${DOCKER_CONFIG:-$HOME/.docker}
mkdir -p $DOCKER_CONFIG/cli-plugins
curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# ---------------------------------------------------------
# EBS Volume Mount (Data Persistence)
# ---------------------------------------------------------
# t3 instances usually map the secondary EBS to nvme1n1. Finding it dynamically:
DEVICE="/dev/$(lsblk -no NAME | grep -v "nvme0n1" | grep "nvme" | head -n 1)"
MOUNT_POINT="/var/lib/elasticsearch_data"

if [ -n "$DEVICE" ]; then
    # Format only if it's raw/empty
    if [ -z "$(lsblk -fno FSTYPE $DEVICE)" ]; then
        sudo mkfs -t xfs $DEVICE
    fi
    
    # Mount it
    sudo mkdir -p $MOUNT_POINT
    sudo mount $DEVICE $MOUNT_POINT
    
    # Add to fstab so it survives reboots
    echo "$DEVICE $MOUNT_POINT xfs defaults,nofail 0 2" | sudo tee -a /etc/fstab
    
    # Elasticsearch container runs as uid 1000, needs ownership of this folder
    sudo chown -R 1000:1000 $MOUNT_POINT
else
    # Fallback in case EBS detection fails
    sudo mkdir -p $MOUNT_POINT
    sudo chown -R 1000:1000 $MOUNT_POINT
fi

# ---------------------------------------------------------
# Workspace & ELK Config
# ---------------------------------------------------------
mkdir -p /home/ec2-user/monitoring
cd /home/ec2-user/monitoring


sudo rm -rf $MOUNT_POINT/*

# Note: Security (xpack) enabled dynamically via Terraform variables
# Heap limited to 1GB to prevent OOM in t3.medium instances.
cat <<EOF > docker-compose.yml
version: '3.8'

services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.12.0
    container_name: elasticsearch
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=true
      - ELASTIC_PASSWORD=${elastic_password}
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
      - ELASTICSEARCH_USERNAME=kibana_system
      - ELASTICSEARCH_PASSWORD=${elastic_password}
      - XPACK_SECURITY_ENABLED=true
      - XPACK_FLEET_ENABLED=true
      - XPACK_ENCRYPTEDSAVEDOBJECTS_ENCRYPTIONKEY=a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6
      - XPACK_FLEET_ENCRYPTIONKEY=q1w2e3r4t5y6u7i8o9p0a1s2d3f4g5h6
      - XPACK_REPORTING_ENCRYPTIONKEY=z1x2c3v4b5n6m7l8k9j0h1g2f3d4s5a6
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

# Fix perms for the monitoring folder
chown -R ec2-user:ec2-user /home/ec2-user/monitoring

# ---------------------------------------------------------
# Run ELK Stack (Secured Bootstrapping Sequence)
# ---------------------------------------------------------
# Start ONLY Elasticsearch first
sudo /usr/local/bin/docker-compose up -d elasticsearch

# Wait patiently for the Elasticsearch API to be ready
echo "Esperando a que Elasticsearch levante..."
until curl -s -u "elastic:${elastic_password}" http://localhost:9200 | grep -q "cluster_name"; do
  sleep 5
done

# Inject the system user's password via the API
echo "Configurando usuario interno de Kibana..."
curl -s -X POST -u "elastic:${elastic_password}" \
  -H "Content-Type: application/json" \
  "http://localhost:9200/_security/user/kibana_system/_password" \
  -d "{\"password\":\"${elastic_password}\"}"

# start kibana
sudo /usr/local/bin/docker-compose up -d kibana

# ---------------------------------------------------------
# Get Elastic Agent (matching ELK version)
# ---------------------------------------------------------
cd /home/ec2-user
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-8.12.0-linux-x86_64.tar.gz
tar xzvf elastic-agent-8.12.0-linux-x86_64.tar.gz
chown -R ec2-user:ec2-user /home/ec2-user/elastic-agent-8.12.0-linux-x86_64

# ---------------------------------------------------------
# Database & Lab Environment Setup
# ---------------------------------------------------------
echo "Configuring database environment..."

# Terraform injects real values here
RDS_ENDPOINT="${rds_endpoint}"
DB_USER="${db_user}"
DB_PASS="${db_pass}"

echo "Waiting for RDS readiness at $RDS_ENDPOINT..."
while ! nc -zv $RDS_ENDPOINT 3306; do
  echo "RDS not available yet... retrying in 10s"
  sleep 10
done

echo "RDS detected. Loading Sakila sample database..."
cd /tmp
wget https://downloads.mysql.com/docs/sakila-db.tar.gz
tar -xvf sakila-db.tar.gz
cd sakila-db
mysql -h $RDS_ENDPOINT -u $DB_USER -p"$DB_PASS" < sakila-schema.sql
mysql -h $RDS_ENDPOINT -u $DB_USER -p"$DB_PASS" < sakila-data.sql

echo "Creating Lab database..."
mysql -h $RDS_ENDPOINT -u $DB_USER -p"$DB_PASS" -e "CREATE DATABASE IF NOT EXISTS lab_elastic; USE lab_elastic; CREATE TABLE IF NOT EXISTS web_metrics (id INT AUTO_INCREMENT PRIMARY KEY, response_time FLOAT, status_code INT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);"

# Create the Lab Telemetry script
cat << 'INNER_EOF' > /home/ec2-user/run_lab.sh
#!/bin/bash
echo "🚀 Telemetry Generator started. Press Ctrl+C to stop..."

# Placeholders to be replaced by sed for security
TARGET_HOST="REPLACE_WITH_ENDPOINT"
DB_USERNAME="REPLACE_WITH_USER"
DB_PASSWORD="REPLACE_WITH_PASS"

while true; do
  # Generate random latency and occasional 500 errors
  RESPONSE_TIME=$(( ( RANDOM % 900 )  + 100 ))
  [ $(( RANDOM % 10 )) -eq 0 ] && HTTP_STATUS=500 || HTTP_STATUS=200
  
  # Insert telemetry data
  mysql -h $TARGET_HOST -u $DB_USERNAME -p"$DB_PASSWORD" -e "INSERT INTO lab_elastic.web_metrics (response_time, status_code) VALUES ($RESPONSE_TIME, $HTTP_STATUS);"
  
  # Cleanup data older than 1 hour to prevent EBS fill-up
  mysql -h $TARGET_HOST -u $DB_USERNAME -p"$DB_PASSWORD" -e "DELETE FROM lab_elastic.web_metrics WHERE created_at < NOW() - INTERVAL 1 HOUR;"
  
  sleep 2
done
INNER_EOF

# Securely inject credentials into the bash script
sed -i "s/REPLACE_WITH_ENDPOINT/$RDS_ENDPOINT/g" /home/ec2-user/run_lab.sh
sed -i "s/REPLACE_WITH_USER/$DB_USER/g" /home/ec2-user/run_lab.sh
sed -i "s/REPLACE_WITH_PASS/$DB_PASS/g" /home/ec2-user/run_lab.sh

# Set correct permissions
chmod +x /home/ec2-user/run_lab.sh
chown ec2-user:ec2-user /home/ec2-user/run_lab.sh

echo "--- Database and Lab Setup Completed Successfully ---"
echo "Wait 2-3 mins for Elastic to be healthy at :5601"

# ---------------------------------------------------------
# Start the Telemetry Generator in the background
# ---------------------------------------------------------
echo "Starting Lab Telemetry Generator..."

# Run the script as ec2-user, in the background, ignoring HUP signals
sudo -u ec2-user nohup /home/ec2-user/run_lab.sh > /home/ec2-user/lab_execution.log 2>&1 &

echo "--- Full Automation Finished ---"