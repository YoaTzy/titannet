#!/bin/bash
# Improved Titan Edge Node Setup Script

# Colors for better readability
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check for root privileges
if [ "$(id -u)" != "0" ]; then
    echo -e "${YELLOW}This script requires root access.${NC}"
    echo -e "${YELLOW}Please enter root mode using 'sudo -i', then rerun this script.${NC}"
    exec sudo -i
    exit 1
fi

# Function for error handling
error_exit() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Create storage directory in /var/lib instead of /root
STORAGE_BASE="/var/lib/titan-edge"
mkdir -p "$STORAGE_BASE" || error_exit "Failed to create storage directory"
chmod 700 "$STORAGE_BASE" # Secure permissions

# Get identity code
echo -e "${YELLOW}Please enter your identity code:${NC}"
read -p "> " id
[[ -z "$id" ]] && error_exit "Identity code cannot be empty"

# Get storage size
read -p "Enter the storage size for each node in GB (default 50): " storage_gb
storage_gb=${storage_gb:-50}
if ! [[ "$storage_gb" =~ ^[0-9]+$ && "$storage_gb" -ge 1 ]]; then
    error_exit "Invalid storage size. Please enter a number greater than 0."
fi

# Get starting port
read -p "Enter the starting port (default 1235): " start_port
start_port=${start_port:-1235}
if ! [[ "$start_port" =~ ^[0-9]+$ && "$start_port" -ge 1024 && "$start_port" -le 65535 ]]; then
    error_exit "Invalid port. Please enter a number between 1024 and 65535."
fi

# Get number of nodes
read -p "Enter the number of nodes to create (max 5, default 5): " container_count
container_count=${container_count:-5}
if ! [[ "$container_count" -ge 1 && "$container_count" -le 5 ]]; then
    error_exit "Invalid number of nodes. Please enter a number between 1 and 5."
fi

# Get public IP
public_ip=$(curl -s ifconfig.me)
[[ -z "$public_ip" ]] && error_exit "No public IP detected. Check your internet connection."

# Install Docker if not present
if ! command -v docker &> /dev/null; then
    echo -e "${GREEN}Docker not detected, installing...${NC}"
    apt-get update -qq || error_exit "Failed to update package lists"
    apt-get install -y ca-certificates curl gnupg lsb-release docker.io || error_exit "Failed to install Docker"
else
    # Check if Docker service is running
    if ! systemctl is-active --quiet docker; then
        echo -e "${YELLOW}Docker installed but not running. Starting Docker...${NC}"
        systemctl start docker || error_exit "Failed to start Docker service"
    else
        echo -e "${GREEN}Docker is already installed and running.${NC}"
    fi
fi

# Pull Docker image with progress indication
echo -e "${GREEN}Pulling the Docker image nezha123/titan-edge...${NC}"
docker pull nezha123/titan-edge || error_exit "Failed to pull Docker image"

# Setup nodes
echo -e "${GREEN}Setting up ${container_count} Titan Edge nodes...${NC}"
current_port=$start_port
created_nodes=()

for ((i=1; i<=container_count; i++)); do
    node_name="titan_${public_ip}_${i}"
    storage_path="${STORAGE_BASE}/${node_name}"
    
    echo -e "${GREEN}Creating node ${i}/${container_count}: ${node_name}${NC}"
    
    # Create storage directory for this node
    mkdir -p "$storage_path" || error_exit "Failed to create storage for node $node_name"
    
    # Run container
    container_id=$(docker run -d --restart always \
        -v "$storage_path:/root/.titanedge/storage" \
        --name "$node_name" \
        --net=host \
        nezha123/titan-edge) || error_exit "Failed to create container for node $node_name"
        
    echo -e "${GREEN}Node $node_name created with container ID: ${container_id:0:12}${NC}"
    created_nodes+=("$node_name")
    
    # Wait for container to initialize
    echo "Waiting for container to initialize..."
    sleep 5
    
    # Configure container
    echo "Configuring node..."
    docker exec $container_id bash -c "\
        sed -i 's/^[[:space:]]*#StorageGB = .*/StorageGB = $storage_gb/' /root/.titanedge/config.toml && \
        sed -i 's/^[[:space:]]*#ListenAddress = \"0.0.0.0:1234\"/ListenAddress = \"0.0.0.0:$current_port\"/' /root/.titanedge/config.toml" || \
        error_exit "Failed to configure node $node_name"
    
    # Restart container to apply changes
    docker restart $container_id || error_exit "Failed to restart node $node_name"
    
    # Wait for restart
    echo "Waiting for node to restart..."
    sleep 10
    
    # Bind node
    echo "Binding node..."
    docker exec $container_id bash -c "\
        titan-edge bind --hash=$id https://api-test1.container1.titannet.io/api/v2/device/binding" || \
        echo -e "${YELLOW}Warning: Binding may have failed for node $node_name. Please check manually.${NC}"
    
    echo -e "${GREEN}✓ Node $node_name setup complete (Port: $current_port, Storage: ${storage_gb}GB)${NC}"
    echo "---------------------------------------------------------"
    
    # Increment port for next node
    current_port=$((current_port + 1))
done

# Create summary
echo -e "\n${GREEN}============================== SETUP SUMMARY ===============================${NC}"
echo -e "Total nodes created: ${#created_nodes[@]}"
echo -e "Storage location: ${STORAGE_BASE}"
echo -e "Public IP: ${public_ip}"
echo -e "Port range: ${start_port}-$((start_port + container_count - 1))"
echo -e "Storage per node: ${storage_gb}GB"
echo -e "\nNode list:"
for node in "${created_nodes[@]}"; do
    echo "- $node"
done

echo -e "\n${GREEN}All nodes have been set up and are running${NC}"
echo -e "${YELLOW}To check status:${NC} docker ps | grep titan"
echo -e "${YELLOW}To view logs:${NC} docker logs [container_name]"
echo -e "${GREEN}============================== SETUP COMPLETE ===============================${NC}"
