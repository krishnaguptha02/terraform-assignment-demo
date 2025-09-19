# GKE Blue-Green Deployment with Auto-Scaling

This project demonstrates a complete GCP GKE (Google Kubernetes Engine) setup with Terraform, Jenkins CI/CD pipeline, and blue-green deployment strategy with auto-scaling capabilities.

## 🏗️ Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Terraform     │    │   GKE Cluster   │    │   Jenkins       │
│   Infrastructure│───▶│   (2 nodes)     │◀───│   CI/CD         │
│   as Code       │    │   Auto-scaling  │    │   Pipeline      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │  Sample App     │
                       │  Blue-Green     │
                       │  Deployment     │
                       └─────────────────┘
```

## 📋 Prerequisites

- GCP account with billing enabled
- `gcloud` CLI installed and configured
- `terraform` >= 1.0 installed
- `kubectl` installed
- `docker` installed
- Jenkins instance (local or cloud)

## 🚀 Quick Start

### 1. Clone and Setup

```bash
git clone <your-repo-url>
cd terraform-assignment
```

### 2. Configure Terraform

```bash
# Copy and edit the variables file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values:
# - project_id: Your GCP project ID
# - region: Your preferred region (default: us-central1)
# - zone: Your preferred zone (default: us-central1-a)
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

### 4. Configure kubectl

```bash
# Get cluster credentials
gcloud container clusters get-credentials gke-cluster --zone us-central1-a --project YOUR_PROJECT_ID
```

### 5. Deploy Application

```bash
# Deploy the sample application
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/blue-deployment.yaml
kubectl apply -f k8s/hpa.yaml
```

## 🔧 Components

### Infrastructure (Terraform)

- **GKE Cluster**: 2-node cluster with auto-scaling enabled
- **VPC Network**: Custom network with subnet
- **Service Accounts**: Dedicated accounts for GKE nodes and Jenkins
- **IAM Roles**: Proper permissions for CI/CD operations
- **Cloud Build**: Trigger for automated deployments

### Application

- **Sample Node.js App**: Express.js application with health checks
- **Docker Container**: Multi-stage build for production
- **Kubernetes Manifests**: Complete K8s resources for deployment

### CI/CD Pipeline

- **Jenkins Pipeline**: Blue-green deployment strategy
- **Docker Registry**: Google Container Registry (GCR)
- **Automated Testing**: Health checks and validation

## 🔄 Blue-Green Deployment Strategy

### How it Works

1. **Blue Environment**: Current production environment
2. **Green Environment**: New version being deployed
3. **Traffic Switch**: Instant switch from blue to green
4. **Rollback**: Easy rollback by switching back to blue

### Deployment Process

```bash
# 1. Deploy Blue version
kubectl apply -f k8s/blue-deployment.yaml

# 2. Deploy Green version
kubectl apply -f k8s/green-deployment.yaml

# 3. Switch traffic to Green
kubectl patch ingress sample-app-ingress -n blue-green-demo -p '{"spec":{"rules":[{"host":"sample-app.example.com","http":{"paths":[{"path":"/","pathType":"Prefix","backend":{"service":{"name":"sample-app-green-service","port":{"number":80}}}}]}}]}}'

# 4. Update HPA to target Green
kubectl patch hpa sample-app-hpa -n blue-green-demo -p '{"spec":{"scaleTargetRef":{"name":"sample-app-green"}}}'
```

## 📈 Auto-Scaling Configuration

### Horizontal Pod Autoscaler (HPA)

- **CPU Threshold**: 70% utilization
- **Memory Threshold**: 80% utilization
- **Min Replicas**: 2
- **Max Replicas**: 10
- **Scale Up**: 50% increase or 2 pods per minute
- **Scale Down**: 10% decrease per minute

### Cluster Autoscaler

- **Min Nodes**: 1
- **Max Nodes**: 5
- **Node Type**: e2-medium
- **Auto-repair**: Enabled
- **Auto-upgrade**: Enabled

## 🧪 Testing

### Test Auto-Scaling

```bash
# Run the auto-scaling test
./scripts/test-autoscaling.sh
```

This script will:
- Generate load on the application
- Monitor HPA scaling behavior
- Display pod and node scaling metrics

### Test Blue-Green Deployment

```bash
# Run the blue-green deployment demo
./scripts/blue-green-deploy.sh
```

This script will:
- Deploy both blue and green versions
- Switch traffic between environments
- Verify deployment health
- Update HPA targets

## 📊 Monitoring and Observability

### Health Checks

- **Liveness Probe**: `/health` endpoint
- **Readiness Probe**: `/health` endpoint
- **Startup Probe**: 30-second initial delay

### Metrics Endpoints

- `/`: Main application endpoint
- `/health`: Health check endpoint
- `/version`: Version information
- `/load`: CPU-intensive endpoint for testing

### Logging

- **Application Logs**: Structured JSON logging
- **Kubernetes Logs**: Available via `kubectl logs`
- **GCP Logging**: Integrated with Cloud Logging

## 🔐 Security Features

- **Private Cluster**: Nodes in private subnet
- **Workload Identity**: Secure service account binding
- **Network Policies**: Enabled for pod-to-pod communication
- **RBAC**: Role-based access control
- **Image Security**: Container image scanning

## 🚨 Troubleshooting

### Common Issues

1. **Cluster Creation Fails**
   ```bash
   # Check API enablement
   gcloud services list --enabled
   
   # Enable required APIs
   gcloud services enable container.googleapis.com
   gcloud services enable compute.googleapis.com
   ```

2. **Deployment Stuck**
   ```bash
   # Check pod status
   kubectl get pods -n blue-green-demo
   
   # Check events
   kubectl get events -n blue-green-demo
   
   # Describe deployment
   kubectl describe deployment sample-app-blue -n blue-green-demo
   ```

3. **Auto-scaling Not Working**
   ```bash
   # Check HPA status
   kubectl get hpa -n blue-green-demo
   
   # Check metrics server
   kubectl top pods -n blue-green-demo
   
   # Check cluster autoscaler
   kubectl get nodes
   ```

### Useful Commands

```bash
# Get cluster info
kubectl cluster-info

# Check all resources
kubectl get all -n blue-green-demo

# View logs
kubectl logs -f deployment/sample-app-blue -n blue-green-demo

# Scale deployment manually
kubectl scale deployment sample-app-blue --replicas=5 -n blue-green-demo

# Port forward for testing
kubectl port-forward service/sample-app-blue-service 8080:80 -n blue-green-demo
```

## 📝 Configuration Files

### Terraform Files
- `main.tf`: Main infrastructure configuration
- `variables.tf`: Input variables
- `outputs.tf`: Output values
- `terraform.tfvars.example`: Example configuration

### Kubernetes Manifests
- `k8s/namespace.yaml`: Namespace definition
- `k8s/blue-deployment.yaml`: Blue environment
- `k8s/green-deployment.yaml`: Green environment
- `k8s/ingress.yaml`: Ingress and SSL configuration
- `k8s/hpa.yaml`: Horizontal Pod Autoscaler

### CI/CD Files
- `Jenkinsfile`: Jenkins pipeline configuration
- `cloudbuild.yaml`: Cloud Build configuration

### Scripts
- `scripts/test-autoscaling.sh`: Auto-scaling test script
- `scripts/blue-green-deploy.sh`: Blue-green deployment script

## 🎯 Demo Scenarios

### Scenario 1: Auto-Scaling Demo

1. Deploy the application
2. Run the load test script
3. Observe HPA scaling up pods
4. Stop the load and watch scaling down

### Scenario 2: Blue-Green Deployment Demo

1. Deploy blue version
2. Deploy green version
3. Switch traffic to green
4. Verify zero-downtime deployment
5. Rollback to blue if needed

## 📚 Additional Resources

- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [Terraform GCP Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Kubernetes HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Blue-Green Deployment](https://martinfowler.com/bliki/BlueGreenDeployment.html)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For issues and questions:
1. Check the troubleshooting section
2. Review GCP and Kubernetes documentation
3. Create an issue in the repository

---

**Note**: This setup is designed for demonstration purposes. For production use, consider additional security measures, monitoring, and backup strategies.
