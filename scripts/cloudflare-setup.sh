#!/bin/bash
# Cloudflare Setup Script for agourakis.com
# BACKUP THIS FILE - Contains all configuration needed

set -e

echo "==================================="
echo "BEAGLE Cloudflare Setup"
echo "Domain: agourakis.com"
echo "==================================="

# Check if .env.cloudflare exists
if [ ! -f .env.cloudflare ]; then
    echo "Creating .env.cloudflare from template..."
    cp .env.cloudflare.example .env.cloudflare
    echo "Please edit .env.cloudflare with your credentials"
    exit 1
fi

# Source environment variables
source .env.cloudflare

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install cloudflared if not present
install_cloudflared() {
    if ! command_exists cloudflared; then
        echo -e "${YELLOW}Installing cloudflared...${NC}"

        # Detect OS
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            # Linux
            wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
            sudo mv cloudflared-linux-amd64 /usr/local/bin/cloudflared
            sudo chmod +x /usr/local/bin/cloudflared
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            brew install cloudflared
        else
            echo -e "${RED}Unsupported OS. Please install cloudflared manually.${NC}"
            exit 1
        fi

        echo -e "${GREEN}cloudflared installed successfully${NC}"
    else
        echo -e "${GREEN}cloudflared already installed${NC}"
    fi
}

# Login to Cloudflare
login_cloudflare() {
    echo -e "${YELLOW}Logging into Cloudflare...${NC}"
    cloudflared tunnel login
}

# Create tunnel
create_tunnel() {
    echo -e "${YELLOW}Creating Cloudflare tunnel: ${CLOUDFLARE_TUNNEL_NAME}${NC}"

    # Check if tunnel already exists
    if cloudflared tunnel list | grep -q ${CLOUDFLARE_TUNNEL_NAME}; then
        echo -e "${YELLOW}Tunnel already exists, skipping creation${NC}"
    else
        cloudflared tunnel create ${CLOUDFLARE_TUNNEL_NAME}
    fi

    # Get tunnel ID
    TUNNEL_ID=$(cloudflared tunnel list | grep ${CLOUDFLARE_TUNNEL_NAME} | awk '{print $1}')
    echo -e "${GREEN}Tunnel ID: ${TUNNEL_ID}${NC}"

    # Save tunnel ID
    echo "CLOUDFLARE_TUNNEL_ID=${TUNNEL_ID}" >> .env.cloudflare.local
}

# Create Kubernetes secret
create_k8s_secret() {
    echo -e "${YELLOW}Creating Kubernetes secret for tunnel credentials...${NC}"

    CREDS_FILE="${HOME}/.cloudflared/${TUNNEL_ID}.json"

    if [ ! -f "${CREDS_FILE}" ]; then
        echo -e "${RED}Credentials file not found: ${CREDS_FILE}${NC}"
        echo "Please run 'cloudflared tunnel create ${CLOUDFLARE_TUNNEL_NAME}' first"
        exit 1
    fi

    # Create namespace if it doesn't exist
    kubectl create namespace cloudflare-system --dry-run=client -o yaml | kubectl apply -f -

    # Create secret
    kubectl create secret generic cloudflared-credentials \
        --from-file=credentials.json="${CREDS_FILE}" \
        -n cloudflare-system \
        --dry-run=client -o yaml | kubectl apply -f -

    echo -e "${GREEN}Kubernetes secret created${NC}"
}

# Setup DNS routes
setup_dns_routes() {
    echo -e "${YELLOW}Setting up DNS routes...${NC}"

    # Main routes
    ROUTES=(
        "api.agourakis.com"
        "ws.agourakis.com"
        "tracing.agourakis.com"
        "metrics.agourakis.com"
        "dashboard.agourakis.com"
        "health.agourakis.com"
        "docs.agourakis.com"
        "status.agourakis.com"
        "dev.agourakis.com"
        "staging.agourakis.com"
        "agourakis.com"
        "www.agourakis.com"
    )

    for route in "${ROUTES[@]}"; do
        echo "Creating route for ${route}..."
        cloudflared tunnel route dns ${CLOUDFLARE_TUNNEL_NAME} ${route} || true
    done

    echo -e "${GREEN}DNS routes configured${NC}"
}

# Deploy to Kubernetes
deploy_to_k8s() {
    echo -e "${YELLOW}Deploying Cloudflare tunnel to Kubernetes...${NC}"

    # Apply configurations
    kubectl apply -f k8s/cloudflare-config.yaml

    echo -e "${GREEN}Deployment complete${NC}"
}

# Verify deployment
verify_deployment() {
    echo -e "${YELLOW}Verifying deployment...${NC}"

    # Wait for pods to be ready
    kubectl wait --for=condition=ready pod -l app=cloudflared -n cloudflare-system --timeout=60s

    # Check pod status
    kubectl get pods -n cloudflare-system

    # Check tunnel status
    cloudflared tunnel info ${CLOUDFLARE_TUNNEL_NAME}

    echo -e "${GREEN}Deployment verified${NC}"
}

# Test connectivity
test_connectivity() {
    echo -e "${YELLOW}Testing connectivity...${NC}"

    # Test endpoints
    ENDPOINTS=(
        "https://health.agourakis.com"
        "https://api.agourakis.com/health"
    )

    for endpoint in "${ENDPOINTS[@]}"; do
        echo "Testing ${endpoint}..."
        if curl -sSf ${endpoint} > /dev/null 2>&1; then
            echo -e "${GREEN}✓ ${endpoint} is reachable${NC}"
        else
            echo -e "${RED}✗ ${endpoint} is not reachable${NC}"
        fi
    done
}

# Backup configuration
backup_config() {
    echo -e "${YELLOW}Creating backup...${NC}"

    BACKUP_DIR="backups/cloudflare-$(date +%Y%m%d-%H%M%S)"
    mkdir -p ${BACKUP_DIR}

    # Copy important files
    cp .env.cloudflare ${BACKUP_DIR}/ 2>/dev/null || true
    cp .env.cloudflare.local ${BACKUP_DIR}/ 2>/dev/null || true
    cp ${HOME}/.cloudflared/*.json ${BACKUP_DIR}/ 2>/dev/null || true
    cp ${HOME}/.cloudflared/cert.pem ${BACKUP_DIR}/ 2>/dev/null || true

    # Export Kubernetes resources
    kubectl get secret cloudflared-credentials -n cloudflare-system -o yaml > ${BACKUP_DIR}/k8s-secret.yaml
    kubectl get configmap cloudflare-config -n cloudflare-system -o yaml > ${BACKUP_DIR}/k8s-configmap.yaml 2>/dev/null || true

    # Create tar archive
    tar -czf ${BACKUP_DIR}.tar.gz ${BACKUP_DIR}
    rm -rf ${BACKUP_DIR}

    echo -e "${GREEN}Backup saved to: ${BACKUP_DIR}.tar.gz${NC}"
    echo -e "${YELLOW}IMPORTANT: Store this backup securely!${NC}"
}

# Main execution flow
main() {
    echo "Starting Cloudflare setup..."

    # Check prerequisites
    if ! command_exists kubectl; then
        echo -e "${RED}kubectl is required but not installed${NC}"
        exit 1
    fi

    # Execute setup steps
    install_cloudflared

    echo ""
    echo "Choose operation:"
    echo "1) Full setup (new installation)"
    echo "2) Update DNS routes only"
    echo "3) Redeploy to Kubernetes"
    echo "4) Backup configuration"
    echo "5) Test connectivity"
    echo "6) All operations"

    read -p "Enter choice [1-6]: " choice

    case $choice in
        1)
            login_cloudflare
            create_tunnel
            create_k8s_secret
            setup_dns_routes
            deploy_to_k8s
            verify_deployment
            backup_config
            ;;
        2)
            setup_dns_routes
            ;;
        3)
            deploy_to_k8s
            verify_deployment
            ;;
        4)
            backup_config
            ;;
        5)
            test_connectivity
            ;;
        6)
            login_cloudflare
            create_tunnel
            create_k8s_secret
            setup_dns_routes
            deploy_to_k8s
            verify_deployment
            test_connectivity
            backup_config
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            exit 1
            ;;
    esac

    echo ""
    echo -e "${GREEN}==================================="
    echo "Setup completed successfully!"
    echo "==================================="
    echo ""
    echo "Next steps:"
    echo "1. Verify DNS propagation: dig api.agourakis.com"
    echo "2. Check tunnel status: cloudflared tunnel info ${CLOUDFLARE_TUNNEL_NAME}"
    echo "3. Monitor pods: kubectl logs -n cloudflare-system -l app=cloudflared -f"
    echo "4. Test endpoints: curl https://health.agourakis.com"
    echo ""
    echo "Important files backed up to: backups/"
    echo -e "${YELLOW}Keep your backup files secure!${NC}"
}

# Run main function
main "$@"
