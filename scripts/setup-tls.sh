#!/bin/bash
# TLS/SSL Setup Script with cert-manager for agourakis.com

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}==================================="
echo "BEAGLE TLS/SSL Setup with cert-manager"
echo "Domain: agourakis.com"
echo "===================================${NC}"

# Check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"

    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}kubectl is required but not installed${NC}"
        exit 1
    fi

    if ! command -v helm &> /dev/null; then
        echo -e "${RED}helm is required but not installed${NC}"
        exit 1
    fi

    echo -e "${GREEN}Prerequisites check passed${NC}"
}

# Install cert-manager
install_cert_manager() {
    echo -e "${YELLOW}Installing cert-manager...${NC}"

    # Add Jetstack Helm repository
    helm repo add jetstack https://charts.jetstack.io
    helm repo update

    # Install cert-manager
    helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --set installCRDs=true \
        --set global.leaderElection.namespace=cert-manager \
        --set prometheus.enabled=true \
        --set prometheus.servicemonitor.enabled=true \
        --version v1.13.0

    # Wait for cert-manager to be ready
    echo -e "${YELLOW}Waiting for cert-manager to be ready...${NC}"
    kubectl wait --for=condition=ready pod \
        -l app=cert-manager -n cert-manager \
        --timeout=300s

    echo -e "${GREEN}cert-manager installed successfully${NC}"
}

# Setup Cloudflare API token secret
setup_cloudflare_secret() {
    echo -e "${YELLOW}Setting up Cloudflare API token secret...${NC}"

    read -sp "Enter your Cloudflare API token: " CF_TOKEN
    echo ""

    # Create secret in cert-manager namespace
    kubectl create secret generic cloudflare-api-token \
        --from-literal=api-token="${CF_TOKEN}" \
        -n cert-manager \
        --dry-run=client -o yaml | kubectl apply -f -

    echo -e "${GREEN}Cloudflare API token secret created${NC}"
}

# Create issuers
create_issuers() {
    echo -e "${YELLOW}Creating Let's Encrypt issuers...${NC}"

    kubectl apply -f k8s/cert-manager.yaml

    # Wait for issuers to be ready
    echo -e "${YELLOW}Waiting for issuers to be ready...${NC}"

    # Check production issuer
    for i in {1..30}; do
        if kubectl get clusterissuer letsencrypt-production -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
            echo -e "${GREEN}Production issuer is ready${NC}"
            break
        fi
        echo "Waiting for production issuer... ($i/30)"
        sleep 10
    done

    # Check staging issuer
    for i in {1..30}; do
        if kubectl get clusterissuer letsencrypt-staging -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
            echo -e "${GREEN}Staging issuer is ready${NC}"
            break
        fi
        echo "Waiting for staging issuer... ($i/30)"
        sleep 10
    done
}

# Request certificate
request_certificate() {
    echo -e "${YELLOW}Requesting TLS certificate...${NC}"

    # The certificate is created by the ingress annotation
    # but we can monitor its status

    echo -e "${YELLOW}Waiting for certificate to be issued...${NC}"

    for i in {1..60}; do
        if kubectl get certificate agourakis-tls -n beagle -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
            echo -e "${GREEN}Certificate issued successfully${NC}"
            return 0
        fi
        echo "Waiting for certificate... ($i/60)"
        sleep 10
    done

    echo -e "${RED}Certificate issuance timed out${NC}"
    echo "Check certificate status with:"
    echo "  kubectl describe certificate agourakis-tls -n beagle"
    echo "  kubectl describe certificaterequest -n beagle"
}

# Verify certificate
verify_certificate() {
    echo -e "${YELLOW}Verifying TLS certificate...${NC}"

    # Get certificate details
    echo ""
    echo "Certificate Details:"
    kubectl get certificate agourakis-tls -n beagle -o wide

    echo ""
    echo "Certificate Secret:"
    kubectl get secret agourakis-tls-secret -n beagle -o wide

    echo ""
    echo "Certificate Expiration:"
    kubectl get certificate agourakis-tls -n beagle -o jsonpath='{.status.notAfter}' 2>/dev/null || echo "Not yet issued"

    echo ""
    echo -e "${YELLOW}Verifying certificate with OpenSSL...${NC}"

    # Extract certificate from secret
    kubectl get secret agourakis-tls-secret -n beagle \
        -o jsonpath='{.data.tls\.crt}' | base64 -d | \
        openssl x509 -text -noout -in /dev/stdin | head -20
}

# Test HTTPS connectivity
test_https() {
    echo -e "${YELLOW}Testing HTTPS connectivity...${NC}"

    ENDPOINTS=(
        "https://agourakis.com"
        "https://api.agourakis.com/health"
        "https://ws.agourakis.com"
        "https://health.agourakis.com"
    )

    for endpoint in "${ENDPOINTS[@]}"; do
        echo ""
        echo "Testing $endpoint..."

        # Check certificate validity
        DOMAIN=$(echo $endpoint | sed 's/https:\/\///g' | cut -d'/' -f1)
        echo "Certificate for $DOMAIN:"

        timeout 5 openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" </dev/null 2>/dev/null | \
            openssl x509 -noout -dates -subject 2>/dev/null || echo "Certificate check failed"

        # Test connectivity
        if curl -sSf -I "$endpoint" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ $endpoint is reachable${NC}"
        else
            echo -e "${YELLOW}⚠ $endpoint returned error (might be DNS propagation delay)${NC}"
        fi
    done
}

# Cleanup
cleanup() {
    echo -e "${YELLOW}Cleanup function called${NC}"

    read -p "Do you want to remove cert-manager? (y/N): " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        helm uninstall cert-manager -n cert-manager
        kubectl delete namespace cert-manager
        echo -e "${GREEN}cert-manager removed${NC}"
    fi
}

# Backup certificates
backup_certificates() {
    echo -e "${YELLOW}Backing up certificates...${NC}"

    BACKUP_DIR="backups/tls-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    # Export secret
    kubectl get secret agourakis-tls-secret -n beagle -o yaml > "$BACKUP_DIR/agourakis-tls-secret.yaml"
    kubectl get certificate agourakis-tls -n beagle -o yaml > "$BACKUP_DIR/agourakis-tls-cert.yaml"

    # Export issuer
    kubectl get clusterissuer letsencrypt-production -o yaml > "$BACKUP_DIR/letsencrypt-production.yaml"

    # Create archive
    tar -czf "${BACKUP_DIR}.tar.gz" "$BACKUP_DIR"
    rm -rf "$BACKUP_DIR"

    echo -e "${GREEN}Backup saved to: ${BACKUP_DIR}.tar.gz${NC}"
}

# Main execution
main() {
    case "${1:-}" in
        install)
            check_prerequisites
            install_cert_manager
            setup_cloudflare_secret
            create_issuers
            request_certificate
            ;;
        verify)
            verify_certificate
            test_https
            ;;
        test)
            test_https
            ;;
        backup)
            backup_certificates
            ;;
        cleanup)
            cleanup
            ;;
        full)
            check_prerequisites
            install_cert_manager
            setup_cloudflare_secret
            create_issuers
            request_certificate
            verify_certificate
            test_https
            backup_certificates
            ;;
        *)
            echo "Usage: $0 {install|verify|test|backup|cleanup|full}"
            echo ""
            echo "Commands:"
            echo "  install   - Install and configure cert-manager"
            echo "  verify    - Verify certificate and test HTTPS"
            echo "  test      - Test HTTPS connectivity"
            echo "  backup    - Backup certificates and secrets"
            echo "  cleanup   - Remove cert-manager"
            echo "  full      - Run complete setup (install + verify + backup)"
            exit 1
            ;;
    esac

    echo ""
    echo -e "${GREEN}==================================="
    echo "TLS/SSL Setup Complete!"
    echo "===================================${NC}"
    echo ""
    echo "Important commands:"
    echo "  kubectl get certificate -n beagle"
    echo "  kubectl describe certificate agourakis-tls -n beagle"
    echo "  kubectl get secret agourakis-tls-secret -n beagle"
    echo ""
    echo "For monitoring:"
    echo "  kubectl logs -n cert-manager -l app=cert-manager -f"
    echo "  kubectl logs -n cert-manager -l app=webhook -f"
}

main "$@"
