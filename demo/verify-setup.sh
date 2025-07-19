#!/bin/bash

# Verification script for K8sGPT Operator Demo
# This script validates the demo environment and shows operational status

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

# Check if cluster exists and is accessible
check_cluster() {
    log_info "Checking Kind cluster: $KIND_CLUSTER_NAME"
    
    if ! kind get clusters | grep -q "^${KIND_CLUSTER_NAME}$"; then
        log_error "Cluster $KIND_CLUSTER_NAME not found"
        return 1
    fi
    
    if ! kubectl cluster-info --context "kind-${KIND_CLUSTER_NAME}" >/dev/null 2>&1; then
        log_error "Cannot connect to cluster $KIND_CLUSTER_NAME"
        return 1
    fi
    
    log_success "Cluster is accessible"
}

# Check namespaces
check_namespaces() {
    log_info "Checking namespaces..."
    
    local namespaces=("$DEMO_NAMESPACE" "$MONITORING_NAMESPACE" "$K8SGPT_NAMESPACE")
    local all_good=true
    
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" >/dev/null 2>&1; then
            echo "  ✓ $ns"
        else
            echo "  ✗ $ns (missing)"
            all_good=false
        fi
    done
    
    if [ "$all_good" = true ]; then
        log_success "All namespaces present"
    else
        log_error "Some namespaces are missing"
        return 1
    fi
}

# Check Prometheus stack
check_prometheus() {
    log_info "Checking Prometheus stack..."
    
    # Check Helm release
    if helm status kube-prometheus-stack -n "$MONITORING_NAMESPACE" >/dev/null 2>&1; then
        log_success "Prometheus stack Helm release found"
    else
        log_error "Prometheus stack Helm release not found"
        return 1
    fi
    
    # Check key deployments
    local deployments=("prometheus-operator" "grafana")
    local all_ready=true
    
    for deploy in "${deployments[@]}"; do
        if kubectl get deployment -n "$MONITORING_NAMESPACE" | grep -q "$deploy"; then
            local ready=$(kubectl get deployment -n "$MONITORING_NAMESPACE" -o jsonpath='{.status.readyReplicas}' "$(kubectl get deployment -n "$MONITORING_NAMESPACE" -o name | grep "$deploy" | head -1)")
            local desired=$(kubectl get deployment -n "$MONITORING_NAMESPACE" -o jsonpath='{.status.replicas}' "$(kubectl get deployment -n "$MONITORING_NAMESPACE" -o name | grep "$deploy" | head -1)")
            
            if [ "$ready" = "$desired" ] && [ "$ready" != "0" ]; then
                echo "  ✓ $deploy ($ready/$desired ready)"
            else
                echo "  ⚠ $deploy ($ready/$desired ready)"
                all_ready=false
            fi
        else
            echo "  ✗ $deploy (not found)"
            all_ready=false
        fi
    done
    
    # Check StatefulSets
    local statefulsets=("prometheus" "alertmanager")
    for sts in "${statefulsets[@]}"; do
        if kubectl get statefulset -n "$MONITORING_NAMESPACE" | grep -q "$sts"; then
            local ready=$(kubectl get statefulset -n "$MONITORING_NAMESPACE" -o jsonpath='{.status.readyReplicas}' "$(kubectl get statefulset -n "$MONITORING_NAMESPACE" -o name | grep "$sts" | head -1)" 2>/dev/null || echo "0")
            local desired=$(kubectl get statefulset -n "$MONITORING_NAMESPACE" -o jsonpath='{.status.replicas}' "$(kubectl get statefulset -n "$MONITORING_NAMESPACE" -o name | grep "$sts" | head -1)" 2>/dev/null || echo "0")
            
            if [ "$ready" = "$desired" ] && [ "$ready" != "0" ]; then
                echo "  ✓ $sts ($ready/$desired ready)"  
            else
                echo "  ⚠ $sts ($ready/$desired ready)"
                all_ready=false
            fi
        else
            echo "  ✗ $sts (not found)"
            all_ready=false
        fi
    done
    
    if [ "$all_ready" = true ]; then
        log_success "Prometheus stack is healthy"
    else
        log_warning "Some Prometheus components are not fully ready"
    fi
}

# Check K8sGPT operator
check_k8sgpt() {
    log_info "Checking K8sGPT operator..."
    
    # Check Helm release
    if helm status k8sgpt-operator -n "$K8SGPT_NAMESPACE" >/dev/null 2>&1; then
        log_success "K8sGPT operator Helm release found"
    else
        log_error "K8sGPT operator Helm release not found"
        return 1
    fi
    
    # Check operator deployment
    if kubectl get deployment k8sgpt-operator -n "$K8SGPT_NAMESPACE" >/dev/null 2>&1; then
        local ready=$(kubectl get deployment k8sgpt-operator -n "$K8SGPT_NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local desired=$(kubectl get deployment k8sgpt-operator -n "$K8SGPT_NAMESPACE" -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
        
        if [ "$ready" = "$desired" ] && [ "$ready" != "0" ]; then
            echo "  ✓ k8sgpt-operator deployment ($ready/$desired ready)"
        else
            echo "  ⚠ k8sgpt-operator deployment ($ready/$desired ready)"
            return 1
        fi
    else
        log_error "K8sGPT operator deployment not found"
        return 1
    fi
    
    # Check K8sGPT custom resource
    if kubectl get k8sgpt -A >/dev/null 2>&1; then
        local count=$(kubectl get k8sgpt -A --no-headers | wc -l)
        echo "  ✓ K8sGPT resources ($count found)"
    else
        log_warning "No K8sGPT resources found"
    fi
    
    # Check interplex (if enabled)
    if kubectl get deployment release-interplex -n "$K8SGPT_NAMESPACE" >/dev/null 2>&1; then
        echo "  ✓ Interplex cache enabled"
    else
        echo "  ⚠ Interplex cache not found"
    fi
    
    log_success "K8sGPT operator is running"
}

# Check webhook simulator
check_webhook_simulator() {
    log_info "Checking webhook simulator..."
    
    if kubectl get deployment k8sgpt-webhook-simulator -n "$DEMO_NAMESPACE" >/dev/null 2>&1; then
        local ready=$(kubectl get deployment k8sgpt-webhook-simulator -n "$DEMO_NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local desired=$(kubectl get deployment k8sgpt-webhook-simulator -n "$DEMO_NAMESPACE" -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
        
        if [ "$ready" = "$desired" ] && [ "$ready" != "0" ]; then
            echo "  ✓ Webhook simulator ($ready/$desired ready)"
            log_success "Webhook simulator is running"
        else
            echo "  ⚠ Webhook simulator ($ready/$desired ready)"
            log_warning "Webhook simulator is not fully ready"
        fi
    else
        log_warning "Webhook simulator not found"
    fi
}

# Check test applications
check_test_apps() {
    log_info "Checking test applications..."
    
    local app_count=$(kubectl get deployments,pods -n "$DEMO_NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [ "$app_count" -gt 0 ]; then
        echo "  ✓ Found $app_count test resources"
        
        # Show problematic pods (which is expected for our test apps)
        local problem_pods=$(kubectl get pods -n "$DEMO_NAMESPACE" --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l || echo "0")
        if [ "$problem_pods" -gt 0 ]; then
            echo "  ⚠ $problem_pods problematic pods (expected for demo)"
        fi
        
        log_success "Test applications are deployed"
    else
        log_warning "No test applications found. Run deploy-test-apps.sh to deploy them."
    fi
}

# Check analysis results
check_analysis_results() {
    log_info "Checking K8sGPT analysis results..."
    
    local result_count=$(kubectl get results -A --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [ "$result_count" -gt 0 ]; then
        echo "  ✓ Found $result_count analysis results"
        log_success "K8sGPT is analyzing and producing results"
        
        # Show recent results
        echo
        echo "=== Recent Analysis Results ==="
        kubectl get results -A --sort-by='.metadata.creationTimestamp' 2>/dev/null | tail -5 || echo "No results to show"
    else
        log_warning "No analysis results found yet. This may be normal if the demo just started."
    fi
}

# Check connectivity and ports
check_connectivity() {
    log_info "Checking service connectivity..."
    
    # Test internal connectivity to webhook simulator
    if kubectl get svc k8sgpt-webhook-sim -n "$DEMO_NAMESPACE" >/dev/null 2>&1; then
        echo "  ✓ Webhook simulator service exists"
    else
        echo "  ✗ Webhook simulator service not found"
    fi
    
    # Check if ports are exposed
    local ports_info=""
    if docker container ls | grep -q "$KIND_CLUSTER_NAME-control-plane"; then
        ports_info=$(docker port "${KIND_CLUSTER_NAME}-control-plane" 2>/dev/null || echo "")
        if echo "$ports_info" | grep -q "9090"; then
            echo "  ✓ Prometheus port (9090) exposed"
        else
            echo "  ⚠ Prometheus port (9090) not exposed"
        fi
        
        if echo "$ports_info" | grep -q "9093"; then
            echo "  ✓ Alertmanager port (9093) exposed"
        else
            echo "  ⚠ Alertmanager port (9093) not exposed"
        fi
        
        if echo "$ports_info" | grep -q "3000"; then
            echo "  ✓ Grafana port (3000) exposed"
        else
            echo "  ⚠ Grafana port (3000) not exposed"
        fi
    fi
}

# Show summary and next steps
show_summary() {
    echo
    log_info "=== Demo Environment Summary ==="
    echo
    echo "Access URLs:"
    echo "  Prometheus:   http://localhost:9090"
    echo "  Alertmanager: http://localhost:9093"
    echo "  Grafana:      http://localhost:3000 (admin/admin123)"
    echo
    echo "Useful Commands:"
    echo "  # Watch K8sGPT results:"
    echo "  watch kubectl get results -A"
    echo
    echo "  # View webhook simulator logs:"
    echo "  kubectl logs -n $DEMO_NAMESPACE -l app=k8sgpt-webhook-simulator -f"
    echo
    echo "  # Check operator logs:"
    echo "  kubectl logs -n $K8SGPT_NAMESPACE -l app.kubernetes.io/name=k8sgpt-operator -f"
    echo
    echo "  # Deploy test apps (if not done):"
    echo "  ./demo/deploy-test-apps.sh"
    echo
    echo "  # Monitor test apps:"
    echo "  ./demo/deploy-test-apps.sh --monitor"
}

# Show detailed status
show_detailed_status() {
    echo
    log_info "=== Detailed Status ==="
    echo
    
    echo "=== K8sGPT Resources ==="
    kubectl get k8sgpt -A 2>/dev/null || echo "No K8sGPT resources found"
    echo
    
    echo "=== Analysis Results ==="
    kubectl get results -A 2>/dev/null | head -10 || echo "No results found"
    echo
    
    echo "=== Test Application Pods ==="
    kubectl get pods -n "$DEMO_NAMESPACE" 2>/dev/null || echo "No test pods found"
    echo
    
    echo "=== Recent Events ==="
    kubectl get events -A --field-selector=type=Warning --sort-by='.metadata.creationTimestamp' 2>/dev/null | tail -5 || echo "No warning events found"
}

# Parse arguments
parse_args() {
    DETAILED=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --detailed)
                DETAILED=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo
                echo "OPTIONS:"
                echo "  --detailed    Show detailed status information"
                echo "  --help        Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    log_info "Verifying K8sGPT Operator Demo Environment"
    echo
    
    local checks_passed=0
    local total_checks=7
    
    check_cluster && ((checks_passed++)) || true
    check_namespaces && ((checks_passed++)) || true  
    check_prometheus && ((checks_passed++)) || true
    check_k8sgpt && ((checks_passed++)) || true
    check_webhook_simulator && ((checks_passed++)) || true
    check_test_apps && ((checks_passed++)) || true
    check_analysis_results && ((checks_passed++)) || true
    check_connectivity
    
    echo
    if [ $checks_passed -eq $total_checks ]; then
        log_success "All critical checks passed ($checks_passed/$total_checks)"
    elif [ $checks_passed -ge $((total_checks - 2)) ]; then
        log_warning "Most checks passed ($checks_passed/$total_checks) - demo should work"
    else
        log_error "Several checks failed ($checks_passed/$total_checks) - demo may not work properly"
    fi
    
    if [ "$DETAILED" = true ]; then
        show_detailed_status
    fi
    
    show_summary
}

# Parse arguments and run
parse_args "$@"
main