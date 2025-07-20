#!/bin/bash

# K8sGPT Operator Comprehensive Demo Setup Script
# This script sets up a complete monitoring and troubleshooting environment

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-k8sgpt-demo}"
DEMO_NAMESPACE="${DEMO_NAMESPACE:-k8sgpt-demo}"
MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
K8SGPT_NAMESPACE="${K8SGPT_NAMESPACE:-k8sgpt-operator-system}"
OPENAI_TOKEN="${OPENAI_TOKEN:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 is not installed. Please install $1 and try again."
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    check_command docker
    check_command kind
    check_command helm
    check_command kubectl
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    
    # Check OpenAI token
    if [[ -z "$OPENAI_TOKEN" ]]; then
        log_error "OPENAI_TOKEN environment variable is required."
        log_info "Please set it with: export OPENAI_TOKEN='your-openai-token'"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Create Kind cluster
create_cluster() {
    log_info "Creating Kind cluster: $KIND_CLUSTER_NAME"
    
    # Check if cluster already exists
    if kind get clusters | grep -q "^${KIND_CLUSTER_NAME}$"; then
        log_warning "Cluster $KIND_CLUSTER_NAME already exists"
        read -p "Do you want to delete and recreate it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deleting existing cluster..."
            kind delete cluster --name "$KIND_CLUSTER_NAME"
        else
            log_info "Using existing cluster"
            kubectl cluster-info --context "kind-${KIND_CLUSTER_NAME}"
            return 0
        fi
    fi
    
    # Create cluster with config
    kind create cluster \
        --name "$KIND_CLUSTER_NAME" \
        --config "$SCRIPT_DIR/kind-config.yaml" \
        --wait 300s
    
    # Set kubectl context
    kubectl cluster-info --context "kind-${KIND_CLUSTER_NAME}"
    log_success "Kind cluster created successfully"
}

# Setup namespaces
setup_namespaces() {
    log_info "Setting up namespaces..."
    
    # Create namespaces
    kubectl create namespace "$DEMO_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace "$MONITORING_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Label namespaces for monitoring
    kubectl label namespace "$DEMO_NAMESPACE" monitoring=enabled --overwrite
    
    log_success "Namespaces created"
}

# Install Prometheus stack
install_prometheus() {
    log_info "Installing Prometheus stack..."
    
    # Add Prometheus helm repo
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    # Create Alertmanager config secret
    kubectl create secret generic alertmanager-config \
        --from-file=alertmanager.yml="$SCRIPT_DIR/alertmanager-config.yaml" \
        -n "$MONITORING_NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Install kube-prometheus-stack
    if helm status kube-prometheus-stack -n "$MONITORING_NAMESPACE" >/dev/null 2>&1; then
        log_warning "Prometheus stack already installed, upgrading..."
        helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
            -n "$MONITORING_NAMESPACE" \
            -f "$SCRIPT_DIR/prometheus-values.yaml" \
            --wait --timeout 10m
    else
        helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
            -n "$MONITORING_NAMESPACE" \
            --create-namespace \
            -f "$SCRIPT_DIR/prometheus-values.yaml" \
            --wait --timeout 10m
    fi
    
    log_success "Prometheus stack installed"
}

# Install K8sGPT operator
install_k8sgpt() {
    log_info "Installing K8sGPT operator..."
    
    # Add K8sGPT helm repo
    helm repo add k8sgpt https://charts.k8sgpt.ai/
    helm repo update
    
    # Create OpenAI secret
    kubectl create secret generic k8sgpt-sample-secret \
        --from-literal=openai-api-key="$OPENAI_TOKEN" \
        -n "$K8SGPT_NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Install K8sGPT operator
    if helm status k8sgpt-operator -n "$K8SGPT_NAMESPACE" >/dev/null 2>&1; then
        log_warning "K8sGPT operator already installed, upgrading..."
        helm upgrade k8sgpt-operator k8sgpt/k8sgpt-operator \
            -n "$K8SGPT_NAMESPACE" \
            -f "$SCRIPT_DIR/k8sgpt-values.yaml" \
            --wait --timeout 10m
    else
        helm install k8sgpt-operator k8sgpt/k8sgpt-operator \
            -n "$K8SGPT_NAMESPACE" \
            --create-namespace \
            -f "$SCRIPT_DIR/k8sgpt-values.yaml" \
            --wait --timeout 10m
    fi
    
    log_success "K8sGPT operator installed"
}

# Create K8sGPT configuration
create_k8sgpt_config() {
    log_info "Creating K8sGPT configuration..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: core.k8sgpt.ai/v1alpha1
kind: K8sGPT
metadata:
  name: k8sgpt-demo-config
  namespace: $K8SGPT_NAMESPACE
spec:
  ai:
    enabled: true
    model: gpt-4o-mini
    backend: openai
    secret:
      name: k8sgpt-sample-secret
      key: openai-api-key
  # Enable webhook sink for demo
  sink:
    type: slack  # Using slack type for webhook functionality
    endpoint: "http://k8sgpt-webhook-sim.${DEMO_NAMESPACE}.svc.cluster.local:8080/alerts"
  # Analysis configuration
  noCache: false
  version: v0.4.1
  repository: ghcr.io/k8sgpt-ai/k8sgpt
  # Enable interplex for caching
  remoteCache:
    interplex:
      endpoint: release-interplex-service.${K8SGPT_NAMESPACE}.svc.cluster.local:8084
EOF
    
    log_success "K8sGPT configuration created"
}

# Deploy webhook simulator and structured data components
deploy_webhook_simulator() {
    log_info "Deploying webhook simulator..."
    
    kubectl apply -f "$SCRIPT_DIR/test-apps/webhook-simulator.yaml"
    
    # Deploy result processor and SNS-like publisher system
    log_info "Deploying structured data processor and publisher..."
    kubectl apply -f "$SCRIPT_DIR/result-processor.yaml"
    kubectl apply -f "$SCRIPT_DIR/publisher-subscriber.yaml"
    
    # Wait for webhook simulator to be ready
    kubectl wait --for=condition=available --timeout=300s deployment/k8sgpt-webhook-simulator -n "$DEMO_NAMESPACE"
    
    # Wait for structured data components to be ready
    kubectl wait --for=condition=available --timeout=300s deployment/k8sgpt-result-processor -n "$DEMO_NAMESPACE"
    kubectl wait --for=condition=available --timeout=300s deployment/k8sgpt-publisher-service -n "$DEMO_NAMESPACE"  
    kubectl wait --for=condition=available --timeout=300s deployment/k8sgpt-subscriber-example -n "$DEMO_NAMESPACE"
    
    log_success "Webhook simulator and structured data components deployed"
}

# Display access information
show_access_info() {
    log_info "Demo environment is ready!"
    echo
    echo "=== Access Information ==="
    echo "Prometheus:   http://localhost:9090"
    echo "Alertmanager: http://localhost:9093" 
    echo "Grafana:      http://localhost:3000 (admin/admin123)"
    echo
    echo "=== Structured Data Endpoints ==="
    echo "# Port forward to access directly:"
    echo "kubectl port-forward -n $DEMO_NAMESPACE svc/k8sgpt-publisher-service 8081:8081 &"
    echo "kubectl port-forward -n $DEMO_NAMESPACE svc/k8sgpt-subscriber-service 8082:8082 &"
    echo "# Then access:"
    echo "Publisher:    http://localhost:8081 (topics, subscriptions, stats)"
    echo "Subscriber:   http://localhost:8082 (analyses, stats)"
    echo
    echo "=== SNS-like Topics ==="
    echo "- k8sgpt.analysis.symptom"
    echo "- k8sgpt.analysis.explanation" 
    echo "- k8sgpt.analysis.diagnosis"
    echo "- k8sgpt.analysis.remediation"
    echo "- k8sgpt.analysis.recommendation"
    echo
    echo "=== Useful Commands ==="
    echo "# Check K8sGPT resources:"
    echo "kubectl get k8sgpt -A"
    echo "kubectl get results -A"
    echo
    echo "# Monitor structured data processing:"
    echo "kubectl logs -n $DEMO_NAMESPACE -l app=k8sgpt-result-processor -f"
    echo "kubectl logs -n $DEMO_NAMESPACE -l app=k8sgpt-publisher -f"
    echo "kubectl logs -n $DEMO_NAMESPACE -l app=k8sgpt-subscriber -f"
    echo
    echo "# Check markdown files generated:"
    echo "kubectl exec -n $DEMO_NAMESPACE deployment/k8sgpt-result-processor -- ls -la /data/structured/"
    echo "kubectl exec -n $DEMO_NAMESPACE deployment/k8sgpt-subscriber-example -- ls -la /data/received/"
    echo
    echo "# Monitor alerts:"
    echo "kubectl logs -n $MONITORING_NAMESPACE -l app.kubernetes.io/name=alertmanager"
    echo
    echo "# Check K8sGPT operator:"
    echo "kubectl logs -n $K8SGPT_NAMESPACE -l app.kubernetes.io/name=k8sgpt-operator"
    echo
    echo "# Deploy test applications:"
    echo "./demo/deploy-test-apps.sh"
    echo
    echo "# Verify setup:"
    echo "./demo/verify-setup.sh"
}

# Main function
main() {
    log_info "Starting K8sGPT Operator Demo Setup"
    
    check_prerequisites
    create_cluster
    setup_namespaces
    install_prometheus
    install_k8sgpt
    create_k8sgpt_config
    deploy_webhook_simulator
    
    log_success "Demo setup completed successfully!"
    show_access_info
}

# Handle interruption
trap 'log_error "Setup interrupted"; exit 1' INT

# Run main function
main "$@"