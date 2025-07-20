# K8sGPT Operator Comprehensive Demo

This demo provides a comprehensive simulation environment for k8sgpt-operator that integrates with Prometheus monitoring and Alertmanager to showcase automated Kubernetes troubleshooting capabilities.

## Architecture Overview

The demo creates a complete monitoring and troubleshooting stack:

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Test Apps     │───▶│   Prometheus     │───▶│  Alertmanager   │
│                 │    │   (Metrics)      │    │   (Alerts)      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                          │
                                                          ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  K8sGPT Result  │◀───│  K8sGPT          │◀───│  Webhook Sink   │
│  Custom Resources│    │  Operator        │    │  (Simulated)    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Key Components

### 1. Kind Cluster
- Local Kubernetes cluster for isolated testing
- Pre-configured with necessary resources

### 2. Prometheus Stack
- **kube-prometheus-stack** Helm chart
- Prometheus server for metrics collection
- Alertmanager for alert routing
- Pre-configured alerting rules for common Kubernetes issues

### 3. K8sGPT Operator
- Deployed via Helm chart
- Configured with AI backend (OpenAI)
- Connected to webhook sink for notifications

### 4. Test Applications
Sample applications that generate specific alert conditions:
- **OOM Application**: Causes Out of Memory alerts
- **CrashLoop Application**: Creates CrashLoopBackOff situations  
- **Readiness Failure App**: Fails readiness probes
- **Resource Starvation App**: Causes resource constraint alerts
- **Missing Image App**: References non-existent container images

### 5. Integration Points

#### Alertmanager → K8sGPT Integration
Since k8sgpt-operator doesn't expose a native webhook endpoint for receiving alerts, the demo uses a hybrid approach:

1. **Alert Simulation**: Alertmanager alerts are captured and logged
2. **K8sGPT Analysis**: The operator performs regular analysis of cluster issues
3. **Result Correlation**: Results are correlated with alert conditions
4. **Sink Notifications**: Analysis results are sent to configured sinks (Slack/webhook)

#### Monitoring Flow
1. Test applications generate problematic conditions
2. Prometheus collects metrics and triggers alerts
3. K8sGPT operator detects issues during analysis cycles
4. AI-powered explanations are generated
5. Results are stored as Custom Resources
6. Notifications are sent to configured sinks

## Demo Scenarios

### Scenario 1: Out of Memory (OOM)
- Deploy memory-intensive application
- Watch Prometheus OOM alerts
- Observe K8sGPT analysis and explanation

### Scenario 2: CrashLoopBackOff
- Deploy application with failing startup
- Monitor CrashLoopBackOff alerts
- Review AI-generated troubleshooting suggestions

### Scenario 3: Resource Constraints
- Deploy resource-hungry applications
- Trigger resource quota alerts
- Analyze capacity planning recommendations

### Scenario 4: Image Pull Failures
- Deploy pods with invalid image references
- Watch ImagePullBackOff alerts
- Get configuration correction suggestions

## Verification Process

### 1. Alert Generation Verification
```bash
kubectl get prometheusrules -A
kubectl get alerts -n monitoring
```

### 2. K8sGPT Analysis Verification
```bash
kubectl get k8sgpt -A
kubectl get results -A
kubectl describe result <result-name>
```

### 3. Sink Notification Verification
```bash
kubectl logs -n k8sgpt-operator-system deployment/k8sgpt-operator
```

## Expected Outputs

### K8sGPT Results
Custom Resources containing:
- Problem identification
- AI-generated explanations
- Suggested remediation steps
- Resource details and context

### Sink Notifications
Webhook payloads containing:
- Alert summaries
- Diagnostic information
- Remediation suggestions
- Links to relevant resources

### Logs and Metrics
- Operator reconciliation logs
- Analysis execution logs
- Prometheus metrics for monitoring
- Alertmanager firing alerts

## Demo Scripts

- `setup.sh`: Complete environment setup
- `deploy-test-apps.sh`: Deploy problematic applications
- `verify-setup.sh`: Validate installation
- `simulate-issues.sh`: Trigger specific scenarios
- `cleanup.sh`: Clean up resources

## Prerequisites

- Docker
- Kind (v0.20.0+)
- Helm (v3.0+)
- kubectl
- OpenAI API key (or compatible AI backend)

## Quick Start

1. Set environment variables:
```bash
export OPENAI_TOKEN="your-openai-token"
export DEMO_NAMESPACE="k8sgpt-demo"
```

2. Run the complete setup:
```bash
./demo/setup.sh
```

3. Deploy test applications:
```bash
./demo/deploy-test-apps.sh
```

4. Monitor and verify:
```bash
./demo/verify-setup.sh
watch kubectl get results -A
```

5. Cleanup when done:
```bash
./demo/cleanup.sh
```

## Configuration Files

- `kind-config.yaml`: Kind cluster configuration
- `prometheus-values.yaml`: Prometheus stack Helm values
- `k8sgpt-values.yaml`: K8sGPT operator Helm values
- `alertmanager-config.yaml`: Custom Alertmanager configuration
- `test-apps/`: Directory containing problematic application manifests

## Troubleshooting

### Common Issues

1. **Missing OpenAI Token**: Set `OPENAI_TOKEN` environment variable
2. **Kind Cluster Issues**: Ensure Docker is running and accessible
3. **Helm Chart Failures**: Check network connectivity and repo updates
4. **Resource Constraints**: Ensure adequate system resources (8GB+ RAM recommended)

### Debug Commands

```bash
# Check k8sgpt operator status
kubectl get pods -n k8sgpt-operator-system

# View operator logs
kubectl logs -n k8sgpt-operator-system -l app.kubernetes.io/name=k8sgpt-operator

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090

# Verify Alertmanager
kubectl port-forward -n monitoring svc/alertmanager-operated 9093:9093
```

## Extension Points

The demo can be extended with:
- Additional test scenarios
- Custom alerting rules
- Integration with other notification systems
- Auto-remediation examples
- Performance testing scenarios