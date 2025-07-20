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

### 4. Structured Data Publishing System
**NEW**: Advanced analysis result processing with SNS-like publishing:
- **Result Processor**: Watches Result CRs and structures analysis into 5 components
- **SNS-like Publisher**: Manages topics, subscriptions, and message delivery
- **Example Subscriber**: Demonstrates application integration patterns

#### Structured Components (Published as Markdown)
1. **Symptom** - What is observed (symptoms, affected components)
2. **Explanation** - What it means (technical context, impact)
3. **Diagnosis** - What's wrong (root cause, contributing factors)
4. **Remediation** - How to fix it (step-by-step resolution)
5. **Recommendation** - Prevention strategies (best practices, monitoring)

#### Topics for Subscription
- `k8sgpt.analysis.symptom` - Alert systems subscribe here
- `k8sgpt.analysis.explanation` - Documentation systems
- `k8sgpt.analysis.diagnosis` - Investigation tools
- `k8sgpt.analysis.remediation` - Automation engines  
- `k8sgpt.analysis.recommendation` - Knowledge bases

See [STRUCTURED_DATA.md](./STRUCTURED_DATA.md) for complete documentation.

### 5. Test Applications
Sample applications that generate specific alert conditions:
- **OOM Application**: Causes Out of Memory alerts
- **CrashLoop Application**: Creates CrashLoopBackOff situations  
- **Readiness Failure App**: Fails readiness probes
- **Resource Starvation App**: Causes resource constraint alerts
- **Missing Image App**: References non-existent container images

### 6. Integration Points

#### Alertmanager → K8sGPT Integration
Since k8sgpt-operator doesn't expose a native webhook endpoint for receiving alerts, the demo uses a hybrid approach:

1. **Alert Simulation**: Alertmanager alerts are captured and logged
2. **K8sGPT Analysis**: The operator performs regular analysis of cluster issues
3. **Result Processing**: Results are structured into standardized components
4. **SNS-like Publishing**: Components published to topics for application subscription
5. **Sink Notifications**: Analysis results are sent to configured sinks (Slack/webhook)

#### Enhanced Monitoring Flow
1. Test applications generate problematic conditions
2. Prometheus collects metrics and triggers alerts
3. K8sGPT operator detects issues during analysis cycles
4. **Result Processor structures analysis into 5 components**
5. **SNS-like Publisher distributes structured data to subscribers**
6. **Applications process structured markdown files for automation/alerting**
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

### 3. Structured Data Processing Verification
```bash
# Check result processor logs
kubectl logs -n k8sgpt-demo -l app=k8sgpt-result-processor -f

# View generated markdown files
kubectl exec -n k8sgpt-demo deployment/k8sgpt-result-processor -- ls -la /data/structured/

# Check specific analysis components
kubectl exec -n k8sgpt-demo deployment/k8sgpt-result-processor -- cat /data/structured/analysis-123_symptom.md
```

### 4. SNS-like Publisher Verification
```bash
# Port forward to access publisher API
kubectl port-forward -n k8sgpt-demo svc/k8sgpt-publisher-service 8081:8081 &

# Check topics and subscriptions
curl http://localhost:8081/topics
curl http://localhost:8081/subscriptions
curl http://localhost:8081/stats
```

### 5. Subscriber Application Verification
```bash
# Port forward to access subscriber API
kubectl port-forward -n k8sgpt-demo svc/k8sgpt-subscriber-service 8082:8082 &

# Check received analyses
curl http://localhost:8082/analyses
curl http://localhost:8082/stats

# View received markdown files
kubectl exec -n k8sgpt-demo deployment/k8sgpt-subscriber-example -- ls -la /data/received/
```

### 6. Sink Notification Verification
```bash
kubectl logs -n k8sgpt-operator-system deployment/k8sgpt-operator
```

## Expected Outputs

### K8sGPT Results (Standard)
Custom Resources containing:
- Problem identification
- AI-generated explanations
- Suggested remediation steps
- Resource details and context

### Structured Data Components (New)
Five markdown files per analysis:
1. **`analysis-id_symptom.md`** - Resource issues and affected components
2. **`analysis-id_explanation.md`** - Technical context and impact assessment
3. **`analysis-id_diagnosis.md`** - Root cause analysis and contributing factors
4. **`analysis-id_remediation.md`** - Step-by-step resolution instructions
5. **`analysis-id_recommendation.md`** - Prevention strategies and best practices

### SNS-like Messages
JSON messages published to topics:
```json
{
  "Type": "Notification",
  "MessageId": "msg-000001", 
  "TopicArn": "arn:k8sgpt:sns:demo:k8sgpt:k8sgpt.analysis.symptom",
  "Message": "{\"analysis_id\":\"pod-issue-1642234200\",\"component\":\"symptom\",\"content\":\"# Symptom...\"}",
  "MessageAttributes": {
    "AnalysisId": "pod-issue-1642234200",
    "Component": "symptom"
  }
}
```

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