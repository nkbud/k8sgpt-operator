# Structured Data Publishing with K8sGPT Operator

This document explains how the k8sgpt-operator demo implements structured data publishing, transforming AI analysis results into organized components published to an SNS-like queue system.

## Architecture Overview

The structured data publishing system consists of three main components:

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   K8sGPT        │───▶│  Result          │───▶│  Result         │
│   Operator      │    │  Custom Resource │    │  Processor      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                          │
                                                          ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Subscriber     │◀───│  SNS-like        │◀───│  Structured     │
│  Applications   │    │  Publisher       │    │  Data Builder   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Current vs Enhanced Approach

### Current Approach (Standard k8sgpt-operator)
- K8sGPT operator creates `Result` custom resources
- Results contain raw analysis text in `details` field and `error` arrays
- Applications must watch/query Result CRs directly
- No standardized structure for analysis components

### Enhanced Approach (This Demo)
- K8sGPT operator still creates `Result` CRs (maintains compatibility)
- **Result Processor** watches Result CRs and extracts structured components
- **SNS-like Publisher** manages topics and subscriptions
- **Subscriber Applications** receive structured markdown files
- Analysis is broken into 5 standardized components

## Structured Components

Each k8sgpt analysis is structured into 5 components:

### 1. Symptom (`symptom.md`)
**What is observed**
- Resource identification (type, name, namespace)
- Detected issues and error conditions
- Affected components
- Timestamp of detection

**Example:**
```markdown
# Symptom

**Resource**: Pod/crashloop-app
**Namespace**: k8sgpt-demo
**Detected At**: 2024-01-15T10:30:00Z

## Observed Issues
- Container failing to start
- CrashLoopBackOff status
- Restart count increasing

## Affected Components
- Pod/crashloop-app
```

### 2. Explanation (`explanation.md`)
**What it means**
- Technical interpretation of the symptoms
- Context about the resource type and configuration
- Impact assessment on application and cluster

**Example:**
```markdown
# Explanation

## What This Means
The pod is experiencing a crash loop where the container starts but immediately exits with an error.

## Technical Context
Resource Type: Pod
Backend: openai
This indicates a fundamental issue with the container startup process.

## Impact Assessment
This issue prevents the application from running and may affect service availability.
```

### 3. Diagnosis (`diagnosis.md`)
**What's wrong**
- Root cause analysis
- Contributing factors
- System state information
- Correlation with other issues

**Example:**
```markdown
# Diagnosis

## Root Cause Analysis
The container command is configured to fail immediately on startup.

## Contributing Factors
- Missing environment variables
- Incorrect container command configuration
- Resource constraints

## System State
Resource: Pod/crashloop-app
Namespace: k8sgpt-demo
Status: CrashLoopBackOff
```

### 4. Remediation (`remediation.md`)
**How to fix it**
- Immediate actions required
- Step-by-step resolution process
- Validation steps
- Commands to execute

**Example:**
```markdown
# Remediation

## Immediate Actions Required
1. Check container logs for specific error messages
2. Verify container command and arguments
3. Review environment variable configuration

## Step-by-Step Resolution
1. Update deployment with correct container command
2. Apply configuration changes
3. Monitor pod status for successful startup

## Validation Steps
1. Verify pod reaches Running state
2. Check application functionality
3. Monitor for recurring crashes
```

### 5. Recommendation (`recommendation.md`)
**Best practices to prevent recurrence**
- Prevention strategies
- Best practices
- Monitoring recommendations
- Long-term improvements

**Example:**
```markdown
# Recommendations

## Prevention Strategies
- Implement proper health checks
- Use init containers for dependency validation
- Test container startup in development

## Best Practices
- Regular health checks for Pod resources
- Implement proper monitoring
- Use declarative configuration with validation

## Monitoring & Alerting
- Set up alerts for pod state changes
- Monitor container restart counts
- Implement readiness and liveness probes

## Long-term Improvements
- Consider implementing GitOps workflows
- Regular configuration validation
- Automated testing for container startup
```

## SNS-like Publishing System

### Topics
Each component is published to a dedicated topic:
- `k8sgpt.analysis.symptom`
- `k8sgpt.analysis.explanation`
- `k8sgpt.analysis.diagnosis`
- `k8sgpt.analysis.remediation`
- `k8sgpt.analysis.recommendation`

### Message Format
Messages follow SNS-style JSON format:
```json
{
  "Type": "Notification",
  "MessageId": "msg-000001",
  "TopicArn": "arn:k8sgpt:sns:demo:k8sgpt:k8sgpt.analysis.symptom",
  "Subject": "K8sGPT Analysis - Symptom",
  "Message": "{\"analysis_id\":\"crashloop-app-1642234200\",\"component\":\"symptom\",\"content\":\"# Symptom\\n...\",\"content_type\":\"text/markdown\",\"timestamp\":\"2024-01-15T10:30:00Z\"}",
  "Timestamp": "2024-01-15T10:30:00Z",
  "MessageAttributes": {
    "AnalysisId": "crashloop-app-1642234200",
    "Component": "symptom"
  }
}
```

### Subscription Model
Applications can subscribe to:
- **All components**: Get complete analysis workflow
- **Specific components**: Only symptoms for alerting, only remediations for automation
- **Multiple topics**: Custom combinations based on use case

## Implementation Details

### Result Processor (`result-processor.yaml`)
- Watches `Result` CRs using Kubernetes watch API
- Extracts and structures analysis using regex and keyword matching
- Publishes structured data to SNS-like system
- Writes markdown files for persistence
- Creates Kubernetes events for audit trail

### Publisher Service (`publisher-subscriber.yaml`)
- HTTP API compatible with SNS operations
- Manages topics, subscriptions, and message delivery
- Handles webhook delivery to subscriber endpoints
- Provides statistics and monitoring
- Simulates AWS SNS functionality

### Subscriber Example (`publisher-subscriber.yaml`)
- Demonstrates application integration pattern
- Subscribes to all analysis topics
- Processes messages by component type
- Generates analysis summaries when complete
- Shows real-world usage patterns

## Usage Examples

### 1. Subscribe to All Analysis Components
```bash
curl -X POST http://localhost:8081/subscribe \
  -H "Content-Type: application/json" \
  -d '{
    "topic_arn": "arn:k8sgpt:sns:demo:k8sgpt:k8sgpt.analysis.symptom",
    "protocol": "http",
    "endpoint": "http://my-app/webhooks/k8sgpt/symptom"
  }'
```

### 2. Monitor Structured Data Processing
```bash
# Watch result processor logs
kubectl logs -n k8sgpt-demo -l app=k8sgpt-result-processor -f

# Check generated markdown files
kubectl exec -n k8sgpt-demo deployment/k8sgpt-result-processor -- ls -la /data/structured/

# View specific analysis component
kubectl exec -n k8sgpt-demo deployment/k8sgpt-result-processor -- cat /data/structured/analysis-123_symptom.md
```

### 3. Access Publisher Statistics
```bash
kubectl port-forward -n k8sgpt-demo svc/k8sgpt-publisher-service 8081:8081 &
curl http://localhost:8081/stats
```

### 4. Check Subscriber Application
```bash
kubectl port-forward -n k8sgpt-demo svc/k8sgpt-subscriber-service 8082:8082 &
curl http://localhost:8082/analyses
```

## Integration Patterns

### 1. Alert Management System
Subscribe to `symptom` topic to trigger immediate alerts:
```python
@app.route('/webhooks/k8sgpt/symptom', methods=['POST'])
def handle_symptom(message):
    data = json.loads(message['Message'])
    analysis_id = data['analysis_id']
    
    # Trigger alert
    alert_manager.create_alert(
        title=f"K8sGPT Analysis: {analysis_id}",
        severity="warning",
        content=data['content']
    )
```

### 2. Automation Engine
Subscribe to `remediation` topic for automated fixes:
```python
@app.route('/webhooks/k8sgpt/remediation', methods=['POST'])
def handle_remediation(message):
    data = json.loads(message['Message'])
    
    # Parse remediation steps
    steps = extract_automation_steps(data['content'])
    
    # Execute if safe
    if is_safe_to_automate(steps):
        automation_engine.execute(steps)
```

### 3. Knowledge Base
Subscribe to all topics to build comprehensive documentation:
```python
def build_knowledge_base(analysis_id, components):
    # Combine all 5 components into searchable documentation
    kb_entry = KnowledgeBaseEntry(
        id=analysis_id,
        symptom=components['symptom'],
        explanation=components['explanation'],
        diagnosis=components['diagnosis'],
        remediation=components['remediation'],
        recommendation=components['recommendation']
    )
    knowledge_base.store(kb_entry)
```

## Benefits

### 1. **Standardized Structure**
- Consistent format across all analysis results
- Easy integration for downstream applications
- Searchable and indexable components

### 2. **Event-Driven Architecture**
- Applications react to analysis results automatically
- Loose coupling between k8sgpt-operator and consumers
- Scalable subscription model

### 3. **Component-Specific Processing**
- Different teams can subscribe to relevant components
- Alerts team gets symptoms, automation team gets remediations
- Reduces noise and improves efficiency

### 4. **Persistence and Audit**
- Markdown files provide human-readable persistence
- Full audit trail of analysis processing
- Easy backup and archival

### 5. **Extensible Design**
- New components can be added without breaking existing subscribers
- Custom analysis types can be supported
- Integration with external systems (real SNS, SQS, etc.)

## Future Enhancements

### 1. **Real SNS/SQS Integration**
Replace simulated publisher with actual AWS SNS/SQS or other message queues

### 2. **Advanced Content Processing**
- Machine learning for better component extraction
- Severity scoring and prioritization
- Correlation with historical data

### 3. **Dashboard Integration**
- Grafana panels for analysis metrics
- Real-time analysis flow visualization
- Subscriber health monitoring

### 4. **Multi-tenancy**
- Namespace-based topic isolation
- RBAC for subscription management
- Team-specific analysis routing

This structured approach transforms k8sgpt-operator from a simple analysis tool into a comprehensive, event-driven troubleshooting platform that integrates seamlessly with existing DevOps workflows.