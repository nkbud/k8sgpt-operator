#!/bin/bash

# Simulate specific issue scenarios for K8sGPT analysis
# This script provides interactive demos of different failure patterns

set -e

# Configuration
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

# Simulate OOM scenario
simulate_oom() {
    log_info "Simulating Out of Memory (OOM) scenario..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: oom-simulator
  namespace: $DEMO_NAMESPACE
  labels:
    demo-type: interactive-simulation
spec:
  replicas: 1
  selector:
    matchLabels:
      app: oom-simulator
  template:
    metadata:
      labels:
        app: oom-simulator
    spec:
      containers:
      - name: memory-consumer
        image: progrium/stress
        args: ["--vm", "1", "--vm-bytes", "200M"]
        resources:
          requests:
            memory: "50Mi"
          limits:
            memory: "100Mi"  # Will cause OOM
EOF
    
    log_success "OOM scenario started"
    log_info "Watching pod status (Press Ctrl+C to stop)..."
    
    kubectl get pods -n "$DEMO_NAMESPACE" -l app=oom-simulator -w &
    watch_pid=$!
    
    # Wait for OOM to occur
    sleep 30
    kill $watch_pid 2>/dev/null || true
    
    log_info "OOM scenario should have triggered. Check K8sGPT analysis:"
    echo "kubectl get results -A"
}

# Simulate CrashLoopBackOff scenario
simulate_crashloop() {
    log_info "Simulating CrashLoopBackOff scenario..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: crashloop-simulator
  namespace: $DEMO_NAMESPACE
  labels:
    demo-type: interactive-simulation
spec:
  replicas: 1
  selector:
    matchLabels:
      app: crashloop-simulator
  template:
    metadata:
      labels:
        app: crashloop-simulator
    spec:
      containers:
      - name: failing-app
        image: busybox:1.35
        command: ["/bin/sh", "-c", "echo 'Starting...'; sleep 5; echo 'Failing now!'; exit 1"]
EOF
    
    log_success "CrashLoopBackOff scenario started"
    log_info "Watching pod restarts (Press Ctrl+C to stop)..."
    
    while true; do
        restarts=$(kubectl get pods -n "$DEMO_NAMESPACE" -l app=crashloop-simulator -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")
        status=$(kubectl get pods -n "$DEMO_NAMESPACE" -l app=crashloop-simulator -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
        
        echo "Pod status: $status, Restarts: $restarts"
        
        if [ "$restarts" -gt 3 ]; then
            log_success "CrashLoopBackOff achieved with $restarts restarts"
            break
        fi
        
        sleep 10
    done
}

# Simulate ImagePullBackOff scenario
simulate_image_pull() {
    log_info "Simulating ImagePullBackOff scenario..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: image-pull-simulator
  namespace: $DEMO_NAMESPACE
  labels:
    demo-type: interactive-simulation
spec:
  replicas: 1
  selector:
    matchLabels:
      app: image-pull-simulator
  template:
    metadata:
      labels:
        app: image-pull-simulator
    spec:
      containers:
      - name: missing-image
        image: nonexistent.registry/fake/image:v999
EOF
    
    log_success "ImagePullBackOff scenario started"
    log_info "Pod should enter ImagePullBackOff state shortly..."
    
    # Wait for ImagePullBackOff
    sleep 10
    kubectl get pods -n "$DEMO_NAMESPACE" -l app=image-pull-simulator
}

# Simulate resource constraints
simulate_resource_constraints() {
    log_info "Simulating resource constraint scenario..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: resource-constraint-simulator
  namespace: $DEMO_NAMESPACE
  labels:
    demo-type: interactive-simulation
spec:
  replicas: 5  # High replica count
  selector:
    matchLabels:
      app: resource-constraint-simulator
  template:
    metadata:
      labels:
        app: resource-constraint-simulator
    spec:
      containers:
      - name: resource-hog
        image: nginx:alpine
        resources:
          requests:
            memory: "1Gi"    # High memory request
            cpu: "500m"      # High CPU request
          limits:
            memory: "2Gi"
            cpu: "1000m"
EOF
    
    log_success "Resource constraint scenario started"
    log_info "Some pods may remain in Pending state due to resource constraints..."
    
    sleep 10
    kubectl get pods -n "$DEMO_NAMESPACE" -l app=resource-constraint-simulator
}

# Simulate network/service issues
simulate_service_issues() {
    log_info "Simulating service connectivity issues..."
    
    # Create a deployment with a service that has mismatched selectors
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: service-issue-simulator
  namespace: $DEMO_NAMESPACE
  labels:
    demo-type: interactive-simulation
spec:
  replicas: 2
  selector:
    matchLabels:
      app: service-issue-app
  template:
    metadata:
      labels:
        app: service-issue-app  # Correct label
    spec:
      containers:
      - name: web-server
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: service-issue-simulator
  namespace: $DEMO_NAMESPACE
  labels:
    demo-type: interactive-simulation
spec:
  selector:
    app: wrong-app-name  # Mismatched selector - will cause no endpoints
  ports:
  - port: 80
    targetPort: 80
EOF
    
    log_success "Service issue scenario started"
    log_info "Service will have no endpoints due to mismatched selector..."
    
    sleep 5
    kubectl get svc,endpoints -n "$DEMO_NAMESPACE" -l demo-type=interactive-simulation
}

# Monitor K8sGPT analysis
monitor_analysis() {
    log_info "Monitoring K8sGPT analysis results..."
    log_info "Press Ctrl+C to stop monitoring"
    
    while true; do
        echo "=== $(date) ==="
        
        echo "Results found:"
        kubectl get results -A --no-headers 2>/dev/null | wc -l || echo "0"
        
        echo "Recent results:"
        kubectl get results -A --sort-by='.metadata.creationTimestamp' 2>/dev/null | tail -3 || echo "No results yet"
        
        echo "Problematic pods:"
        kubectl get pods -n "$DEMO_NAMESPACE" --field-selector=status.phase!=Running 2>/dev/null | grep -v NAME || echo "None"
        
        echo "---"
        sleep 30
    done
}

# Clean up simulation resources
cleanup_simulations() {
    log_info "Cleaning up simulation resources..."
    
    kubectl delete deployments,services -n "$DEMO_NAMESPACE" -l demo-type=interactive-simulation --ignore-not-found=true
    
    log_success "Simulation resources cleaned up"
}

# Show available scenarios
show_scenarios() {
    echo "Available simulation scenarios:"
    echo
    echo "1. oom           - Out of Memory (OOM) kills"
    echo "2. crashloop     - CrashLoopBackOff failure"
    echo "3. image-pull    - ImagePullBackOff issues"
    echo "4. resources     - Resource constraint problems"
    echo "5. service       - Service connectivity issues"
    echo "6. monitor       - Monitor K8sGPT analysis results"
    echo "7. cleanup       - Clean up all simulation resources"
    echo
    echo "Examples:"
    echo "  $0 oom          # Simulate OOM scenario"
    echo "  $0 monitor      # Monitor analysis results"
    echo "  $0 cleanup      # Clean up simulations"
}

# Interactive scenario selection
interactive_mode() {
    while true; do
        echo
        show_scenarios
        echo
        read -p "Select a scenario (1-7) or 'q' to quit: " choice
        
        case $choice in
            1|oom)
                simulate_oom
                ;;
            2|crashloop)
                simulate_crashloop
                ;;
            3|image-pull)
                simulate_image_pull
                ;;
            4|resources)
                simulate_resource_constraints
                ;;
            5|service)
                simulate_service_issues
                ;;
            6|monitor)
                monitor_analysis
                ;;
            7|cleanup)
                cleanup_simulations
                ;;
            q|quit|exit)
                log_info "Exiting interactive mode"
                break
                ;;
            *)
                log_error "Invalid choice: $choice"
                ;;
        esac
    done
}

# Show usage
show_usage() {
    echo "Usage: $0 [SCENARIO] [OPTIONS]"
    echo
    echo "SCENARIOS:"
    show_scenarios
    echo
    echo "OPTIONS:"
    echo "  --interactive   Run in interactive mode"
    echo "  --help          Show this help message"
    echo
    echo "If no scenario is specified, runs in interactive mode."
}

# Main function
main() {
    local scenario="$1"
    
    if [ -z "$scenario" ] || [ "$scenario" = "--interactive" ]; then
        log_info "K8sGPT Issue Simulation - Interactive Mode"
        interactive_mode
        return
    fi
    
    case "$scenario" in
        oom)
            simulate_oom
            ;;
        crashloop)
            simulate_crashloop
            ;;
        image-pull)
            simulate_image_pull
            ;;
        resources)
            simulate_resource_constraints
            ;;
        service)
            simulate_service_issues
            ;;
        monitor)
            monitor_analysis
            ;;
        cleanup)
            cleanup_simulations
            ;;
        --help)
            show_usage
            ;;
        *)
            log_error "Unknown scenario: $scenario"
            show_usage
            exit 1
            ;;
    esac
}

# Handle interruption
trap 'echo; log_info "Simulation interrupted"; exit 0' INT

# Run main function
main "$@"