# Deployment Guide

This guide provides step-by-step instructions for deploying the GKE Blue-Green deployment solution.

## Prerequisites Checklist

- [ ] GCP account with billing enabled
- [ ] `gcloud` CLI installed and authenticated
- [ ] `terraform` >= 1.0 installed
- [ ] `kubectl` installed
- [ ] `docker` installed
- [ ] Jenkins instance (optional for manual deployment)

## Step 1: GCP Project Setup

### 1.1 Create a New GCP Project

```bash
# Create a new project (replace with your project name)
gcloud projects create gke-blue-green-demo --name="GKE Blue-Green Demo"

# Set the project as active
gcloud config set project gke-blue-green-demo

# Enable billing (required for GKE)
# Note: You'll need to do this through the GCP Console
```

### 1.2 Enable Required APIs

```bash
# Enable required Google Cloud APIs
gcloud services enable container.googleapis.com
gcloud services enable compute.googleapis.com
gcloud services enable cloudbuild.googleapis.com
gcloud services enable containerregistry.googleapis.com
```

### 1.3 Configure Authentication

```bash
# Authenticate with GCP
gcloud auth login
gcloud auth application-default login

# Configure Docker for GCR
gcloud auth configure-docker
```

## Step 2: Terraform Configuration

### 2.1 Update Configuration

```bash
# Copy the example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values
nano terraform.tfvars
```

Update the following values in `terraform.tfvars`:
```hcl
project_id   = "gke-blue-green-demo"  # Your actual project ID
region       = "us-central1"          # Your preferred region
zone         = "us-central1-a"        # Your preferred zone
github_owner = "your-github-username" # Your GitHub username
github_repo  = "gke-blue-green-deployment" # Your repository name
```

### 2.2 Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply

# Confirm with 'yes' when prompted
```

**Expected Output:**
- GKE cluster with 2 nodes
- VPC network and subnet
- Service accounts with proper permissions
- Cloud Build trigger

## Step 3: Configure kubectl

### 3.1 Get Cluster Credentials

```bash
# Get the project ID from Terraform output
PROJECT_ID=$(terraform output -raw project_id)
ZONE=$(terraform output -raw cluster_location)

# Get cluster credentials
gcloud container clusters get-credentials gke-cluster --zone $ZONE --project $PROJECT_ID

# Verify connection
kubectl cluster-info
```

### 3.2 Verify Cluster Access

```bash
# Check nodes
kubectl get nodes

# Check system pods
kubectl get pods -n kube-system
```

## Step 4: Build and Push Application

### 4.1 Build Docker Image

```bash
# Navigate to app directory
cd app

# Build the Docker image
docker build -t gcr.io/$PROJECT_ID/sample-app:latest .

# Tag for blue-green deployment
docker tag gcr.io/$PROJECT_ID/sample-app:latest gcr.io/$PROJECT_ID/sample-app:blue
docker tag gcr.io/$PROJECT_ID/sample-app:latest gcr.io/$PROJECT_ID/sample-app:green
```

### 4.2 Push to Google Container Registry

```bash
# Push all tags
docker push gcr.io/$PROJECT_ID/sample-app:latest
docker push gcr.io/$PROJECT_ID/sample-app:blue
docker push gcr.io/$PROJECT_ID/sample-app:green
```

## Step 5: Deploy Application

### 5.1 Update Kubernetes Manifests

```bash
# Update image references in deployment files
sed -i "s/gcr.io\/PROJECT_ID/gcr.io\/$PROJECT_ID/g" k8s/blue-deployment.yaml
sed -i "s/gcr.io\/PROJECT_ID/gcr.io\/$PROJECT_ID/g" k8s/green-deployment.yaml
```

### 5.2 Deploy to Kubernetes

```bash
# Create namespace
kubectl apply -f k8s/namespace.yaml

# Deploy blue version
kubectl apply -f k8s/blue-deployment.yaml

# Deploy HPA
kubectl apply -f k8s/hpa.yaml

# Verify deployment
kubectl get pods -n blue-green-demo
kubectl get services -n blue-green-demo
kubectl get hpa -n blue-green-demo
```

## Step 6: Test the Deployment

### 6.1 Basic Health Check

```bash
# Port forward to the service
kubectl port-forward service/sample-app-blue-service 8080:80 -n blue-green-demo &

# Test the application
curl http://localhost:8080/health
curl http://localhost:8080/

# Stop port forward
pkill -f "kubectl port-forward"
```

### 6.2 Test Auto-Scaling

```bash
# Make the script executable
chmod +x scripts/test-autoscaling.sh

# Run the auto-scaling test
./scripts/test-autoscaling.sh
```

**Expected Behavior:**
- HPA should scale up pods when CPU/memory usage increases
- Pods should scale down when load decreases
- Monitor the scaling behavior in the output

## Step 7: Blue-Green Deployment Demo

### 7.1 Deploy Green Version

```bash
# Deploy green version
kubectl apply -f k8s/green-deployment.yaml

# Verify both versions are running
kubectl get pods -n blue-green-demo
```

### 7.2 Run Blue-Green Deployment Script

```bash
# Make the script executable
chmod +x scripts/blue-green-deploy.sh

# Run the blue-green deployment demo
./scripts/blue-green-deploy.sh
```

**Expected Behavior:**
- Both blue and green versions should be healthy
- Traffic should switch from blue to green
- HPA should update to target green deployment
- Zero-downtime deployment achieved

## Step 8: Jenkins Setup (Optional)

### 8.1 Install Jenkins

```bash
# Install Jenkins (Ubuntu/Debian)
wget -q -O - https://pkg.jenkins.io/debian/jenkins.io.key | sudo apt-key add -
sudo sh -c 'echo deb https://pkg.jenkins.io/debian binary/ > /etc/apt/sources.list.d/jenkins.list'
sudo apt update
sudo apt install jenkins

# Start Jenkins
sudo systemctl start jenkins
sudo systemctl enable jenkins
```

### 8.2 Configure Jenkins

1. Access Jenkins at `http://your-server:8080`
2. Install required plugins:
   - Google Kubernetes Engine Plugin
   - Docker Pipeline Plugin
   - Google Container Registry Auth Plugin

3. Configure GCP credentials:
   - Go to Manage Jenkins > Manage Credentials
   - Add Google Service Account key
   - Add Docker Hub credentials (if needed)

### 8.3 Create Jenkins Pipeline

1. Create a new Pipeline job
2. Configure the pipeline to use the `Jenkinsfile` from this repository
3. Set up webhook triggers (optional)

## Step 9: Monitoring and Verification

### 9.1 Check Cluster Status

```bash
# Check cluster autoscaling
kubectl get nodes
kubectl describe nodes

# Check HPA status
kubectl get hpa -n blue-green-demo
kubectl describe hpa sample-app-hpa -n blue-green-demo
```

### 9.2 Monitor Application Logs

```bash
# View application logs
kubectl logs -f deployment/sample-app-blue -n blue-green-demo

# View all pods logs
kubectl logs -f -l app=sample-app -n blue-green-demo
```

### 9.3 Test Load Generation

```bash
# Generate load manually
for i in {1..100}; do
  curl http://localhost:8080/load &
done
wait

# Monitor scaling
watch kubectl get pods -n blue-green-demo
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Terraform Apply Fails

**Error**: API not enabled
```bash
# Enable required APIs
gcloud services enable container.googleapis.com
gcloud services enable compute.googleapis.com
```

**Error**: Quota exceeded
```bash
# Check quotas in GCP Console
# Request quota increase if needed
```

#### 2. kubectl Connection Issues

**Error**: Unable to connect to cluster
```bash
# Re-authenticate
gcloud auth login
gcloud container clusters get-credentials gke-cluster --zone us-central1-a --project YOUR_PROJECT_ID
```

#### 3. Pods Not Starting

**Error**: ImagePullBackOff
```bash
# Check image exists
gcloud container images list --repository gcr.io/YOUR_PROJECT_ID

# Rebuild and push image
docker build -t gcr.io/YOUR_PROJECT_ID/sample-app:latest .
docker push gcr.io/YOUR_PROJECT_ID/sample-app:latest
```

#### 4. HPA Not Scaling

**Error**: HPA shows unknown metrics
```bash
# Check metrics server
kubectl get deployment metrics-server -n kube-system

# Install metrics server if missing
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

## Cleanup

### Remove Resources

```bash
# Delete Kubernetes resources
kubectl delete namespace blue-green-demo

# Destroy Terraform infrastructure
terraform destroy

# Confirm with 'yes' when prompted
```

### Verify Cleanup

```bash
# Check that cluster is deleted
gcloud container clusters list

# Check that images are removed (optional)
gcloud container images list --repository gcr.io/YOUR_PROJECT_ID
```

## Next Steps

1. **Production Considerations**:
   - Set up proper monitoring with Prometheus/Grafana
   - Configure log aggregation
   - Implement backup strategies
   - Set up alerting

2. **Security Enhancements**:
   - Enable Pod Security Standards
   - Configure Network Policies
   - Implement RBAC
   - Use Workload Identity

3. **CI/CD Improvements**:
   - Add automated testing
   - Implement canary deployments
   - Add security scanning
   - Set up notification systems

## Support

For issues and questions:
1. Check the troubleshooting section above
2. Review GCP and Kubernetes documentation
3. Check the main README.md file
4. Create an issue in the repository

---

**Note**: This deployment guide assumes you're using a trial GCP account. Some features may have limitations or require billing to be enabled.
