#!/bin/bash

# Cleanup script for K8sGPT Operator Demo
# This script removes all demo resources and optionally the Kind cluster

set -e

# Configuration
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-k8sgpt-demo}"
DEMO_NAMESPACE="${DEMO_NAMESPACE:-k8sgpt-demo}"
MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
K8SGPT_NAMESPACE="${K8SGPT_NAMESPACE:-k8sgpt-operator-system}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Clean up test applications
cleanup_test_apps() {
    log_info "Cleaning up test applications..."
    
    # Delete test applications by label
    kubectl delete deployments,services,pods,pvc -n "$DEMO_NAMESPACE" -l demo-scenario --ignore-not-found=true
    
    # Delete webhook simulator
    kubectl delete deployment,service k8sgpt-webhook-simulator -n "$DEMO_NAMESPACE" --ignore-not-found=true
    
    # Delete any remaining test resources
    kubectl delete -f ./test-apps/ --ignore-not-found=true >/dev/null 2>&1 || true
    
    log_success "Test applications cleaned up"
}

# Clean up K8sGPT resources
cleanup_k8sgpt() {
    log_info "Cleaning up K8sGPT operator..."
    
    # Delete K8sGPT custom resources
    kubectl delete k8sgpt --all -A --ignore-not-found=true
    
    # Delete analysis results
    kubectl delete results --all -A --ignore-not-found=true
    
    # Uninstall K8sGPT operator Helm release
    if helm status k8sgpt-operator -n "$K8SGPT_NAMESPACE" >/dev/null 2>&1; then
        helm uninstall k8sgpt-operator -n "$K8SGPT_NAMESPACE"
        log_success "K8sGPT operator uninstalled"
    else
        log_warning "K8sGPT operator Helm release not found"
    fi
}

# Clean up Prometheus stack
cleanup_prometheus() {
    log_info "Cleaning up Prometheus stack..."
    
    # Uninstall Prometheus stack Helm release
    if helm status kube-prometheus-stack -n "$MONITORING_NAMESPACE" >/dev/null 2>&1; then
        helm uninstall kube-prometheus-stack -n "$MONITORING_NAMESPACE"
        log_success "Prometheus stack uninstalled"
    else
        log_warning "Prometheus stack Helm release not found"
    fi
    
    # Clean up CRDs (optional, can be left for future use)
    if [ "$CLEAN_CRDS" = "true" ]; then
        log_info "Cleaning up Prometheus CRDs..."
        kubectl delete crd -l app.kubernetes.io/name=kube-prometheus-stack --ignore-not-found=true
    fi
}

# Clean up namespaces
cleanup_namespaces() {
    log_info "Cleaning up namespaces..."
    
    local namespaces=("$DEMO_NAMESPACE" "$MONITORING_NAMESPACE" "$K8SGPT_NAMESPACE")
    
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" >/dev/null 2>&1; then
            log_info "Deleting namespace: $ns"
            kubectl delete namespace "$ns" --ignore-not-found=true
            
            # Wait for namespace to be fully deleted
            log_info "Waiting for namespace $ns to be deleted..."
            kubectl wait --for=delete namespace "$ns" --timeout=120s 2>/dev/null || true
        fi
    done
    
    log_success "Namespaces cleaned up"
}

# Clean up PVCs and PVs
cleanup_storage() {
    log_info "Cleaning up persistent storage..."
    
    # Delete PVCs in demo namespaces
    kubectl delete pvc --all -n "$DEMO_NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    kubectl delete pvc --all -n "$MONITORING_NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    kubectl delete pvc --all -n "$K8SGPT_NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    
    log_success "Storage cleaned up"
}

# Delete Kind cluster
delete_cluster() {
    log_info "Deleting Kind cluster: $KIND_CLUSTER_NAME"
    
    if kind get clusters | grep -q "^${KIND_CLUSTER_NAME}$"; then
        kind delete cluster --name "$KIND_CLUSTER_NAME"
        log_success "Kind cluster deleted"
    else
        log_warning "Kind cluster $KIND_CLUSTER_NAME not found"
    fi
}

# Show cleanup options
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "OPTIONS:"
    echo "  --apps-only     Clean up only test applications"
    echo "  --k8sgpt-only   Clean up only K8sGPT operator"  
    echo "  --prometheus-only Clean up only Prometheus stack"
    echo "  --keep-cluster  Clean up resources but keep Kind cluster"
    echo "  --delete-cluster Delete Kind cluster only"
    echo "  --clean-crds    Also clean up Custom Resource Definitions"
    echo "  --force         Skip confirmation prompts"
    echo "  --help          Show this help message"
    echo
    echo "EXAMPLES:"
    echo "  $0                     # Full cleanup with confirmation"
    echo "  $0 --force             # Full cleanup without confirmation"
    echo "  $0 --apps-only         # Clean up only test applications"
    echo "  $0 --keep-cluster      # Clean up resources but keep cluster"
    echo "  $0 --delete-cluster    # Delete only the Kind cluster"
}

# Confirm cleanup
confirm_cleanup() {
    if [ "$FORCE" != "true" ]; then
        echo
        log_warning "This will delete the following:"
        [ "$CLEANUP_APPS" = "true" ] && echo "  - Test applications and webhook simulator"
        [ "$CLEANUP_K8SGPT" = "true" ] && echo "  - K8sGPT operator and custom resources"
        [ "$CLEANUP_PROMETHEUS" = "true" ] && echo "  - Prometheus stack and monitoring"
        [ "$CLEANUP_NAMESPACES" = "true" ] && echo "  - Demo namespaces"
        [ "$DELETE_CLUSTER" = "true" ] && echo "  - Kind cluster: $KIND_CLUSTER_NAME"
        echo
        
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled"
            exit 0
        fi
    fi
}

# Parse arguments
parse_args() {
    CLEANUP_APPS=true
    CLEANUP_K8SGPT=true
    CLEANUP_PROMETHEUS=true
    CLEANUP_NAMESPACES=true
    DELETE_CLUSTER=true
    CLEAN_CRDS=false
    FORCE=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --apps-only)
                CLEANUP_K8SGPT=false
                CLEANUP_PROMETHEUS=false
                CLEANUP_NAMESPACES=false
                DELETE_CLUSTER=false
                shift
                ;;
            --k8sgpt-only)
                CLEANUP_APPS=false
                CLEANUP_PROMETHEUS=false
                CLEANUP_NAMESPACES=false
                DELETE_CLUSTER=false
                shift
                ;;
            --prometheus-only)
                CLEANUP_APPS=false
                CLEANUP_K8SGPT=false
                CLEANUP_NAMESPACES=false
                DELETE_CLUSTER=false
                shift
                ;;
            --keep-cluster)
                DELETE_CLUSTER=false
                shift
                ;;
            --delete-cluster)
                CLEANUP_APPS=false
                CLEANUP_K8SGPT=false
                CLEANUP_PROMETHEUS=false
                CLEANUP_NAMESPACES=false
                shift
                ;;
            --clean-crds)
                CLEAN_CRDS=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    log_info "K8sGPT Operator Demo Cleanup"
    
    # Check if cluster exists before cleanup
    if [ "$DELETE_CLUSTER" != "true" ] && ! kind get clusters | grep -q "^${KIND_CLUSTER_NAME}$"; then
        log_error "Kind cluster $KIND_CLUSTER_NAME not found"
        exit 1
    fi
    
    confirm_cleanup
    
    # Execute cleanup steps in order
    if [ "$CLEANUP_APPS" = "true" ]; then
        cleanup_test_apps
    fi
    
    if [ "$CLEANUP_K8SGPT" = "true" ]; then
        cleanup_k8sgpt
    fi
    
    if [ "$CLEANUP_PROMETHEUS" = "true" ]; then
        cleanup_prometheus
    fi
    
    # Clean up storage before namespaces
    cleanup_storage
    
    if [ "$CLEANUP_NAMESPACES" = "true" ]; then
        cleanup_namespaces
    fi
    
    if [ "$DELETE_CLUSTER" = "true" ]; then
        delete_cluster
    fi
    
    echo
    log_success "Cleanup completed successfully!"
    
    if [ "$DELETE_CLUSTER" != "true" ]; then
        log_info "Kind cluster $KIND_CLUSTER_NAME is still running"
    fi
}

# Handle interruption
trap 'log_error "Cleanup interrupted"; exit 1' INT

# Parse arguments and run
parse_args "$@"
main