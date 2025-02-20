#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

if [ "$(id -u)" != "0" ]; then
    echo -e "${YELLOW}This script requires root access.${NC}"
    echo -e "${YELLOW}Please enter root mode using 'sudo -i', then rerun this script.${NC}"
    exec sudo -i
    exit 1
fi

echo -e "${YELLOW}Please enter your identity code:${NC}"
read -p "> " id

# Interaksi untuk menentukan ukuran disk
while true; do
    read -p "Enter the storage size for each node in GB (default 50): " storage_gb
    storage_gb=${storage_gb:-50}
    if [[ "$storage_gb" =~ ^[0-9]+$ && "$storage_gb" -ge 1 ]]; then
        break
    else
        echo -e "${YELLOW}Please enter a valid number greater than 0.${NC}"
    fi
done

# Interaksi untuk menentukan port awal
while true; do
    read -p "Enter the starting port (default 1235): " start_port
    start_port=${start_port:-1235}
    if [[ "$start_port" =~ ^[0-9]+$ && "$start_port" -ge 1024 && "$start_port" -le 65535 ]]; then
        break
    else
        echo -e "${YELLOW}Please enter a valid port number between 1024 and 65535.${NC}"
    fi
done

# Interaksi untuk memilih jumlah node
while true; do
    read -p "Enter the number of nodes to create (max 5, default 5): " container_count
    container_count=${container_count:-5}
    if [[ "$container_count" -ge 1 && "$container_count" -le 5 ]]; then
        break
    else
        echo -e "${YELLOW}Please enter a valid number between 1 and 5.${NC}"
    fi
done

public_ips=$(curl -s ifconfig.me)

if [ -z "$public_ips" ]; then
    echo -e "${YELLOW}No public IP detected.${NC}"
    exit 1
fi

if ! command -v docker &> /dev/null
then
    echo -e "${GREEN}Docker not detected, installing...${NC}"
    apt-get update
    apt-get install ca-certificates curl gnupg lsb-release -y
    apt-get install docker.io -y
else
    echo -e "${GREEN}Docker is already installed.${NC}"
fi

echo -e "${GREEN}Pulling the Docker image nezha123/titan-edge...${NC}"
docker pull nezha123/titan-edge

current_port=$start_port

for ip in $public_ips; do
    echo -e "${GREEN}Setting up nodes for IP $ip${NC}"

    for ((i=1; i<=container_count; i++))
    do
        storage_path="/root/.titan_storage/${ip}_${i}"

        mkdir -p "$storage_path"

        container_id=$(docker run -d --restart always -v "$storage_path:/root/.titanedge/storage" --name "titan_${ip}_${i}" --net=host nezha123/titan-edge)

        echo -e "${GREEN}Node titan_${ip}_${i} is running with container ID $container_id${NC}"

        sleep 30

        docker exec $container_id bash -c "\
            sed -i 's/^[[:space:]]*#StorageGB = .*/StorageGB = $storage_gb/' /root/.titanedge/config.toml && \
            sed -i 's/^[[:space:]]*#ListenAddress = \"0.0.0.0:1234\"/ListenAddress = \"0.0.0.0:$current_port\"/' /root/.titanedge/config.toml && \
            echo 'Storage for node titan_${ip}_${i} set to $storage_gb GB, Port set to $current_port'"

        docker restart $container_id

        docker exec $container_id bash -c "\
            titan-edge bind --hash=$id https://api-test1.container1.titannet.io/api/v2/device/binding"
        echo -e "${GREEN}Node titan_${ip}_${i} has been bound.${NC}"

        current_port=$((current_port + 1))
    done
done


echo -e "${GREEN}============================== All nodes have been set up and are running ===============================${NC}"

