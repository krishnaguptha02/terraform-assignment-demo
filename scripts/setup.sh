#!/bin/bash

# Setup Script for GKE Blue-Green Deployment
# This script automates the initial setup process

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    local missing_tools=()
    
    if ! command_exists gcloud; then
        missing_tools+=("gcloud")
    fi
    
    if ! command_exists terraform; then
        missing_tools+=("terraform")
    fi
    
    if ! command_exists kubectl; then
        missing_tools+=("kubectl")
    fi
    
    if ! command_exists docker; then
        missing_tools+=("docker")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_status "Please install the missing tools and run this script again."
        exit 1
    fi
    
    print_success "All prerequisites are installed"
}

# Function to setup GCP authentication
setup_gcp_auth() {
    print_status "Setting up GCP authentication..."
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        print_status "Please authenticate with GCP..."
        gcloud auth login
    fi
    
    # Set up application default credentials
    gcloud auth application-default login
    
    # Configure Docker for GCR
    gcloud auth configure-docker
    
    print_success "GCP authentication configured"
}

# Function to setup project
setup_project() {
    print_status "Setting up GCP project..."
    
    # Get current project
    local current_project=$(gcloud config get-value project 2>/dev/null || echo "")
    
    if [ -z "$current_project" ]; then
        print_error "No GCP project is set. Please set a project:"
        print_status "gcloud config set project YOUR_PROJECT_ID"
        exit 1
    fi
    
    print_success "Using project: $current_project"
    
    # Enable required APIs
    print_status "Enabling required APIs..."
    gcloud services enable container.googleapis.com
    gcloud services enable compute.googleapis.com
    gcloud services enable cloudbuild.googleapis.com
    gcloud services enable containerregistry.googleapis.com
    
    print_success "Required APIs enabled"
}

# Function to setup Terraform
setup_terraform() {
    print_status "Setting up Terraform..."
    
    # Check if terraform.tfvars exists
    if [ ! -f "terraform.tfvars" ]; then
        if [ -f "terraform.tfvars.example" ]; then
            print_status "Creating terraform.tfvars from example..."
            cp terraform.tfvars.example terraform.tfvars
            
            # Get project ID
            local project_id=$(gcloud config get-value project)
            
            # Update project ID in terraform.tfvars
            sed -i.bak "s/your-gcp-project-id/$project_id/g" terraform.tfvars
            rm terraform.tfvars.bak
            
            print_warning "Please review and update terraform.tfvars with your specific values"
        else
            print_error "terraform.tfvars.example not found"
            exit 1
        fi
    fi
    
    # Initialize Terraform
    terraform init
    
    print_success "Terraform initialized"
}

# Function to deploy infrastructure
deploy_infrastructure() {
    print_status "Deploying infrastructure with Terraform..."
    
    # Plan the deployment
    terraform plan
    
    # Ask for confirmation
    read -p "Do you want to apply the Terraform configuration? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        terraform apply -auto-approve
        print_success "Infrastructure deployed successfully"
    else
        print_warning "Infrastructure deployment skipped"
        return 1
    fi
}

# Function to setup kubectl
setup_kubectl() {
    print_status "Setting up kubectl..."
    
    # Get cluster credentials
    local project_id=$(gcloud config get-value project)
    local zone=$(terraform output -raw cluster_location 2>/dev/null || echo "us-central1-a")
    
    gcloud container clusters get-credentials gke-cluster --zone $zone --project $project_id
    
    # Verify connection
    if kubectl cluster-info >/dev/null 2>&1; then
        print_success "kubectl configured successfully"
    else
        print_error "Failed to configure kubectl"
        exit 1
    fi
}

# Function to build and push Docker images
build_and_push_images() {
    print_status "Building and pushing Docker images..."
    
    local project_id=$(gcloud config get-value project)
    
    # Build images
    cd app
    docker build -t gcr.io/$project_id/sample-app:latest .
    docker tag gcr.io/$project_id/sample-app:latest gcr.io/$project_id/sample-app:blue
    docker tag gcr.io/$project_id/sample-app:latest gcr.io/$project_id/sample-app:green
    cd ..
    
    # Push images
    docker push gcr.io/$project_id/sample-app:latest
    docker push gcr.io/$project_id/sample-app:blue
    docker push gcr.io/$project_id/sample-app:green
    
    print_success "Docker images built and pushed"
}

# Function to deploy application
deploy_application() {
    print_status "Deploying application to GKE..."
    
    local project_id=$(gcloud config get-value project)
    
    # Update image references in deployment files
    sed -i.bak "s/gcr.io\/PROJECT_ID/gcr.io\/$project_id/g" k8s/blue-deployment.yaml
    sed -i.bak "s/gcr.io\/PROJECT_ID/gcr.io\/$project_id/g" k8s/green-deployment.yaml
    rm k8s/*.bak
    
    # Deploy to Kubernetes
    kubectl apply -f k8s/namespace.yaml
    kubectl apply -f k8s/blue-deployment.yaml
    kubectl apply -f k8s/hpa.yaml
    
    # Wait for deployment to be ready
    kubectl rollout status deployment/sample-app-blue -n blue-green-demo --timeout=300s
    
    print_success "Application deployed successfully"
}

# Function to verify deployment
verify_deployment() {
    print_status "Verifying deployment..."
    
    # Check pods
    kubectl get pods -n blue-green-demo
    
    # Check services
    kubectl get services -n blue-green-demo
    
    # Check HPA
    kubectl get hpa -n blue-green-demo
    
    # Test health endpoint
    kubectl port-forward service/sample-app-blue-service 8080:80 -n blue-green-demo &
    local port_forward_pid=$!
    
    sleep 10
    
    if curl -f http://localhost:8080/health >/dev/null 2>&1; then
        print_success "Application is healthy"
    else
        print_error "Application health check failed"
    fi
    
    # Clean up port forward
    kill $port_forward_pid 2>/dev/null || true
}

# Main function
main() {
    echo "=========================================="
    echo "GKE Blue-Green Deployment Setup"
    echo "=========================================="
    echo
    
    check_prerequisites
    setup_gcp_auth
    setup_project
    setup_terraform
    
    if deploy_infrastructure; then
        setup_kubectl
        build_and_push_images
        deploy_application
        verify_deployment
        
        echo
        print_success "Setup completed successfully!"
        echo
        print_status "Next steps:"
        echo "1. Run './scripts/test-autoscaling.sh' to test auto-scaling"
        echo "2. Run './scripts/blue-green-deploy.sh' to test blue-green deployment"
        echo "3. Check the README.md for more information"
    else
        print_warning "Setup incomplete. Please run the remaining steps manually."
    fi
}

# Run main function
main "$@"
