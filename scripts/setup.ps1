# Setup Script for GKE Blue-Green Deployment on Windows
# This script automates the initial setup process

param(
    [string]$ProjectId = "",
    [string]$Region = "us-central1",
    [string]$Zone = "us-central1-a"
)

# Function to print colored output
function Write-Status {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Function to check if command exists
function Test-Command {
    param([string]$Command)
    try {
        Get-Command $Command -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

# Function to check prerequisites
function Test-Prerequisites {
    Write-Status "Checking prerequisites..."
    
    $missingTools = @()
    
    if (-not (Test-Command "gcloud")) {
        $missingTools += "gcloud"
    }
    
    if (-not (Test-Command "terraform")) {
        $missingTools += "terraform"
    }
    
    if (-not (Test-Command "kubectl")) {
        $missingTools += "kubectl"
    }
    
    if (-not (Test-Command "docker")) {
        $missingTools += "docker"
    }
    
    if ($missingTools.Count -gt 0) {
        Write-Error "Missing required tools: $($missingTools -join ', ')"
        Write-Status "Please install the missing tools and run this script again."
        exit 1
    }
    
    Write-Success "All prerequisites are installed"
}

# Function to setup GCP authentication
function Set-GCPAuth {
    Write-Status "Setting up GCP authentication..."
    
    # Check if user is authenticated
    $activeAccounts = gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>$null
    if (-not $activeAccounts) {
        Write-Status "Please authenticate with GCP..."
        gcloud auth login
    }
    
    # Set up application default credentials
    gcloud auth application-default login
    
    # Configure Docker for GCR
    gcloud auth configure-docker
    
    Write-Success "GCP authentication configured"
}

# Function to setup project
function Set-Project {
    Write-Status "Setting up GCP project..."
    
    # Get current project
    $currentProject = gcloud config get-value project 2>$null
    
    if (-not $currentProject) {
        Write-Error "No GCP project is set. Please set a project:"
        Write-Status "gcloud config set project YOUR_PROJECT_ID"
        exit 1
    }
    
    Write-Success "Using project: $currentProject"
    
    # Enable required APIs
    Write-Status "Enabling required APIs..."
    gcloud services enable container.googleapis.com
    gcloud services enable compute.googleapis.com
    gcloud services enable cloudbuild.googleapis.com
    gcloud services enable containerregistry.googleapis.com
    
    Write-Success "Required APIs enabled"
}

# Function to setup Terraform
function Set-Terraform {
    Write-Status "Setting up Terraform..."
    
    # Check if terraform.tfvars exists
    if (-not (Test-Path "terraform.tfvars")) {
        if (Test-Path "terraform.tfvars.example") {
            Write-Status "Creating terraform.tfvars from example..."
            Copy-Item "terraform.tfvars.example" "terraform.tfvars"
            
            # Get project ID
            $projectId = gcloud config get-value project
            
            # Update project ID in terraform.tfvars
            (Get-Content "terraform.tfvars") -replace "your-gcp-project-id", $projectId | Set-Content "terraform.tfvars"
            
            Write-Warning "Please review and update terraform.tfvars with your specific values"
        } else {
            Write-Error "terraform.tfvars.example not found"
            exit 1
        }
    }
    
    # Initialize Terraform
    terraform init
    
    Write-Success "Terraform initialized"
}

# Function to deploy infrastructure
function Deploy-Infrastructure {
    Write-Status "Deploying infrastructure with Terraform..."
    
    # Plan the deployment
    terraform plan
    
    # Ask for confirmation
    $confirm = Read-Host "Do you want to apply the Terraform configuration? (y/n)"
    if ($confirm -eq "y" -or $confirm -eq "Y") {
        terraform apply -auto-approve
        Write-Success "Infrastructure deployed successfully"
        return $true
    } else {
        Write-Warning "Infrastructure deployment skipped"
        return $false
    }
}

# Function to setup kubectl
function Set-Kubectl {
    Write-Status "Setting up kubectl..."
    
    # Get cluster credentials
    $projectId = gcloud config get-value project
    $zone = terraform output -raw cluster_location 2>$null
    if (-not $zone) {
        $zone = "us-central1-a"
    }
    
    gcloud container clusters get-credentials gke-cluster --zone $zone --project $projectId
    
    # Verify connection
    try {
        kubectl cluster-info | Out-Null
        Write-Success "kubectl configured successfully"
    } catch {
        Write-Error "Failed to configure kubectl"
        exit 1
    }
}

# Function to build and push Docker images
function Build-PushImages {
    Write-Status "Building and pushing Docker images..."
    
    $projectId = gcloud config get-value project
    
    # Build images
    Set-Location "app"
    docker build -t "gcr.io/$projectId/sample-app:latest" .
    docker tag "gcr.io/$projectId/sample-app:latest" "gcr.io/$projectId/sample-app:blue"
    docker tag "gcr.io/$projectId/sample-app:latest" "gcr.io/$projectId/sample-app:green"
    Set-Location ".."
    
    # Push images
    docker push "gcr.io/$projectId/sample-app:latest"
    docker push "gcr.io/$projectId/sample-app:blue"
    docker push "gcr.io/$projectId/sample-app:green"
    
    Write-Success "Docker images built and pushed"
}

# Function to deploy application
function Deploy-Application {
    Write-Status "Deploying application to GKE..."
    
    $projectId = gcloud config get-value project
    
    # Update image references in deployment files
    (Get-Content "k8s/blue-deployment.yaml") -replace "gcr.io/PROJECT_ID", "gcr.io/$projectId" | Set-Content "k8s/blue-deployment.yaml"
    (Get-Content "k8s/green-deployment.yaml") -replace "gcr.io/PROJECT_ID", "gcr.io/$projectId" | Set-Content "k8s/green-deployment.yaml"
    
    # Deploy to Kubernetes
    kubectl apply -f k8s/namespace.yaml
    kubectl apply -f k8s/blue-deployment.yaml
    kubectl apply -f k8s/hpa.yaml
    
    # Wait for deployment to be ready
    kubectl rollout status deployment/sample-app-blue -n blue-green-demo --timeout=300s
    
    Write-Success "Application deployed successfully"
}

# Function to verify deployment
function Test-Deployment {
    Write-Status "Verifying deployment..."
    
    # Check pods
    kubectl get pods -n blue-green-demo
    
    # Check services
    kubectl get services -n blue-green-demo
    
    # Check HPA
    kubectl get hpa -n blue-green-demo
    
    # Test health endpoint
    $portForwardJob = Start-Job -ScriptBlock {
        kubectl port-forward service/sample-app-blue-service 8080:80 -n blue-green-demo
    }
    
    Start-Sleep -Seconds 10
    
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:8080/health" -Method Get
        Write-Success "Application is healthy"
    } catch {
        Write-Error "Application health check failed"
    } finally {
        # Clean up port forward
        $portForwardJob | Stop-Job
        $portForwardJob | Remove-Job
    }
}

# Main function
function Main {
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "GKE Blue-Green Deployment Setup (Windows)" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    
    Test-Prerequisites
    Set-GCPAuth
    Set-Project
    Set-Terraform
    
    if (Deploy-Infrastructure) {
        Set-Kubectl
        Build-PushImages
        Deploy-Application
        Test-Deployment
        
        Write-Host ""
        Write-Success "Setup completed successfully!"
        Write-Host ""
        Write-Status "Next steps:"
        Write-Host "1. Run '.\scripts\test-autoscaling.ps1' to test auto-scaling"
        Write-Host "2. Run '.\scripts\blue-green-deploy.ps1' to test blue-green deployment"
        Write-Host "3. Check the README.md for more information"
    } else {
        Write-Warning "Setup incomplete. Please run the remaining steps manually."
    }
}

# Run main function
Main
