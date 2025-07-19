#!/bin/bash

# Deploy test applications that generate various alert conditions
# This script demonstrates different failure scenarios for K8sGPT analysis

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_NAMESPACE="${DEMO_NAMESPACE:-k8sgpt-demo}"

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

# Check if namespace exists
check_namespace() {
    if ! kubectl get namespace "$DEMO_NAMESPACE" >/dev/null 2>&1; then
        log_error "Namespace $DEMO_NAMESPACE does not exist. Please run setup.sh first."
        exit 1
    fi
}

# Deploy application with scenario selection
deploy_application() {
    local app_file="$1"
    local app_name="$2"
    local description="$3"
    
    log_info "Deploying $app_name - $description"
    
    if kubectl apply -f "$SCRIPT_DIR/test-apps/$app_file"; then
        log_success "$app_name deployed"
    else
        log_error "Failed to deploy $app_name"
        return 1
    fi
}

# Deploy all applications or specific ones
deploy_apps() {
    local scenario="$1"
    
    case "$scenario" in
        "all"|"")
            log_info "Deploying all test applications..."
            deploy_application "oom-application.yaml" "OOM Application" "Memory pressure causing OOM kills"
            deploy_application "crashloop-application.yaml" "CrashLoop Application" "Application that fails to start"
            deploy_application "readiness-failure.yaml" "Readiness Failure" "Application that never becomes ready"
            deploy_application "missing-image.yaml" "Missing Image" "Pod with non-existent container image"
            deploy_application "resource-starvation.yaml" "Resource Starvation" "Applications with excessive resource requests"
            ;;
        "oom")
            deploy_application "oom-application.yaml" "OOM Application" "Memory pressure causing OOM kills"
            ;;
        "crashloop")
            deploy_application "crashloop-application.yaml" "CrashLoop Application" "Application that fails to start"
            ;;
        "readiness")
            deploy_application "readiness-failure.yaml" "Readiness Failure" "Application that never becomes ready"
            ;;
        "image")
            deploy_application "missing-image.yaml" "Missing Image" "Pod with non-existent container image"
            ;;
        "resources")
            deploy_application "resource-starvation.yaml" "Resource Starvation" "Applications with excessive resource requests"
            ;;
        *)
            log_error "Unknown scenario: $scenario"
            show_usage
            exit 1
            ;;
    esac
}

# Show deployment status
show_status() {
    log_info "Deployment Status:"
    echo
    echo "=== Pods ==="
    kubectl get pods -n "$DEMO_NAMESPACE" -o wide
    echo
    echo "=== Services ==="
    kubectl get svc -n "$DEMO_NAMESPACE"
    echo
    echo "=== PVCs ==="
    kubectl get pvc -n "$DEMO_NAMESPACE" 2>/dev/null || true
    echo
    echo "=== Events (last 10) ==="
    kubectl get events -n "$DEMO_NAMESPACE" --sort-by='.metadata.creationTimestamp' | tail -10
}

# Monitor for issues
monitor_issues() {
    log_info "Monitoring for issues (Press Ctrl+C to stop)..."
    echo
    
    while true; do
        echo "=== $(date) ==="
        
        # Check for problematic pods
        kubectl get pods -n "$DEMO_NAMESPACE" --field-selector=status.phase!=Running 2>/dev/null | grep -v "NAME" || echo "No problematic pods found"
        
        # Check for recent events  
        kubectl get events -n "$DEMO_NAMESPACE" --field-selector=type=Warning --sort-by='.metadata.creationTimestamp' 2>/dev/null | tail -3 | grep -v "NAME" || echo "No recent warning events"
        
        echo "---"
        sleep 30
    done
}

# Show usage
show_usage() {
    echo "Usage: $0 [SCENARIO] [OPTIONS]"
    echo
    echo "SCENARIOS:"
    echo "  all         Deploy all test applications (default)"
    echo "  oom         Deploy OOM application only"
    echo "  crashloop   Deploy crashloop application only"  
    echo "  readiness   Deploy readiness failure application only"
    echo "  image       Deploy missing image application only"
    echo "  resources   Deploy resource starvation application only"
    echo
    echo "OPTIONS:"
    echo "  --status    Show deployment status after deployment"
    echo "  --monitor   Monitor for issues after deployment" 
    echo "  --help      Show this help message"
    echo
    echo "EXAMPLES:"
    echo "  $0                    # Deploy all applications"
    echo "  $0 oom --status       # Deploy OOM app and show status"
    echo "  $0 all --monitor      # Deploy all apps and monitor issues"
}

# Parse command line arguments
parse_args() {
    SCENARIO="all"
    SHOW_STATUS=false
    MONITOR=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --status)
                SHOW_STATUS=true
                shift
                ;;
            --monitor)
                MONITOR=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            oom|crashloop|readiness|image|resources|all)
                SCENARIO="$1"
                shift
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
    log_info "Deploying K8sGPT Demo Test Applications"
    
    check_namespace
    deploy_apps "$SCENARIO"
    
    # Wait a moment for deployments to process
    sleep 5
    
    if [ "$SHOW_STATUS" = true ] || [ "$MONITOR" = true ]; then
        show_status
    fi
    
    if [ "$MONITOR" = true ]; then
        echo
        log_info "Starting monitoring mode..."
        monitor_issues
    else
        echo
        log_success "Test applications deployed successfully!"
        echo
        log_info "Next steps:"
        echo "1. Check deployment status: $0 --status"
        echo "2. Monitor for issues: $0 --monitor"
        echo "3. Verify K8sGPT analysis: kubectl get results -A"
        echo "4. Check webhook logs: kubectl logs -n $DEMO_NAMESPACE -l app=k8sgpt-webhook-simulator"
    fi
}

# Handle interruption for monitoring
trap 'echo; log_info "Monitoring stopped"; exit 0' INT

# Parse arguments and run
parse_args "$@"
main