# Build Script for GKE Blue-Green Deployment on Windows
# This script provides build automation commands similar to Makefile

param(
    [string]$Command = "help",
    [string]$ProjectId = "",
    [string]$Region = "us-central1",
    [string]$Zone = "us-central1-a",
    [string]$ClusterName = "gke-cluster",
    [string]$AppName = "sample-app",
    [string]$Namespace = "blue-green-demo"
)

# Get project ID if not provided
if (-not $ProjectId) {
    $ProjectId = gcloud config get-value project
}

function Show-Help {
    Write-Host "Available commands:" -ForegroundColor Cyan
    Write-Host "  init        - Initialize Terraform" -ForegroundColor Green
    Write-Host "  plan        - Plan Terraform deployment" -ForegroundColor Green
    Write-Host "  apply       - Apply Terraform configuration" -ForegroundColor Green
    Write-Host "  destroy     - Destroy Terraform infrastructure" -ForegroundColor Green
    Write-Host "  build       - Build Docker image" -ForegroundColor Green
    Write-Host "  push        - Push Docker images to GCR" -ForegroundColor Green
    Write-Host "  deploy      - Deploy application to GKE" -ForegroundColor Green
    Write-Host "  deploy-green - Deploy green version" -ForegroundColor Green
    Write-Host "  switch-to-green - Switch traffic to green" -ForegroundColor Green
    Write-Host "  switch-to-blue - Switch traffic to blue" -ForegroundColor Green
    Write-Host "  test        - Run auto-scaling tests" -ForegroundColor Green
    Write-Host "  test-blue-green - Test blue-green deployment" -ForegroundColor Green
    Write-Host "  status      - Show deployment status" -ForegroundColor Green
    Write-Host "  logs        - Show application logs" -ForegroundColor Green
    Write-Host "  logs-green  - Show green deployment logs" -ForegroundColor Green
    Write-Host "  port-forward - Port forward to blue service" -ForegroundColor Green
    Write-Host "  port-forward-green - Port forward to green service" -ForegroundColor Green
    Write-Host "  clean       - Clean up resources" -ForegroundColor Green
    Write-Host "  setup       - Complete setup (init, apply, build, push, deploy)" -ForegroundColor Green
    Write-Host "  all         - Complete setup and run tests" -ForegroundColor Green
}

function Invoke-Init {
    Write-Host "Initializing Terraform..." -ForegroundColor Blue
    terraform init
}

function Invoke-Plan {
    Write-Host "Planning Terraform deployment..." -ForegroundColor Blue
    terraform plan
}

function Invoke-Apply {
    Write-Host "Applying Terraform configuration..." -ForegroundColor Blue
    terraform apply
}

function Invoke-Destroy {
    Write-Host "Destroying Terraform infrastructure..." -ForegroundColor Blue
    terraform destroy
}

function Invoke-Build {
    Write-Host "Building Docker image..." -ForegroundColor Blue
    Set-Location "app"
    docker build -t "gcr.io/$ProjectId/$AppName`:latest" .
    docker tag "gcr.io/$ProjectId/$AppName`:latest" "gcr.io/$ProjectId/$AppName`:blue"
    docker tag "gcr.io/$ProjectId/$AppName`:latest" "gcr.io/$ProjectId/$AppName`:green"
    Set-Location ".."
}

function Invoke-Push {
    Write-Host "Pushing Docker images to GCR..." -ForegroundColor Blue
    docker push "gcr.io/$ProjectId/$AppName`:latest"
    docker push "gcr.io/$ProjectId/$AppName`:blue"
    docker push "gcr.io/$ProjectId/$AppName`:green"
}

function Invoke-Deploy {
    Write-Host "Deploying application to GKE..." -ForegroundColor Blue
    kubectl apply -f k8s/namespace.yaml
    kubectl apply -f k8s/blue-deployment.yaml
    kubectl apply -f k8s/hpa.yaml
}

function Invoke-DeployGreen {
    Write-Host "Deploying green version..." -ForegroundColor Blue
    kubectl apply -f k8s/green-deployment.yaml
}

function Invoke-SwitchToGreen {
    Write-Host "Switching traffic to green..." -ForegroundColor Blue
    $ingressPatch = @{
        spec = @{
            rules = @(
                @{
                    host = "sample-app.example.com"
                    http = @{
                        paths = @(
                            @{
                                path = "/"
                                pathType = "Prefix"
                                backend = @{
                                    service = @{
                                        name = "sample-app-green-service"
                                        port = @{
                                            number = 80
                                        }
                                    }
                                }
                            }
                        )
                    }
                }
            )
        }
    } | ConvertTo-Json -Depth 10

    kubectl patch ingress sample-app-ingress -n $Namespace -p $ingressPatch
    
    $hpaPatch = @{
        spec = @{
            scaleTargetRef = @{
                name = "sample-app-green"
            }
        }
    } | ConvertTo-Json -Depth 5

    kubectl patch hpa sample-app-hpa -n $Namespace -p $hpaPatch
}

function Invoke-SwitchToBlue {
    Write-Host "Switching traffic to blue..." -ForegroundColor Blue
    $ingressPatch = @{
        spec = @{
            rules = @(
                @{
                    host = "sample-app.example.com"
                    http = @{
                        paths = @(
                            @{
                                path = "/"
                                pathType = "Prefix"
                                backend = @{
                                    service = @{
                                        name = "sample-app-blue-service"
                                        port = @{
                                            number = 80
                                        }
                                    }
                                }
                            }
                        )
                    }
                }
            )
        }
    } | ConvertTo-Json -Depth 10

    kubectl patch ingress sample-app-ingress -n $Namespace -p $ingressPatch
    
    $hpaPatch = @{
        spec = @{
            scaleTargetRef = @{
                name = "sample-app-blue"
            }
        }
    } | ConvertTo-Json -Depth 5

    kubectl patch hpa sample-app-hpa -n $Namespace -p $hpaPatch
}

function Invoke-Test {
    Write-Host "Running auto-scaling tests..." -ForegroundColor Blue
    & ".\scripts\test-autoscaling.ps1"
}

function Invoke-TestBlueGreen {
    Write-Host "Testing blue-green deployment..." -ForegroundColor Blue
    & ".\scripts\blue-green-deploy.ps1"
}

function Invoke-Status {
    Write-Host "Showing deployment status..." -ForegroundColor Blue
    kubectl get all -n $Namespace
    kubectl get hpa -n $Namespace
    kubectl get ingress -n $Namespace
}

function Invoke-Logs {
    Write-Host "Showing application logs..." -ForegroundColor Blue
    kubectl logs -f deployment/sample-app-blue -n $Namespace
}

function Invoke-LogsGreen {
    Write-Host "Showing green deployment logs..." -ForegroundColor Blue
    kubectl logs -f deployment/sample-app-green -n $Namespace
}

function Invoke-PortForward {
    Write-Host "Port forwarding to blue service..." -ForegroundColor Blue
    kubectl port-forward service/sample-app-blue-service 8080:80 -n $Namespace
}

function Invoke-PortForwardGreen {
    Write-Host "Port forwarding to green service..." -ForegroundColor Blue
    kubectl port-forward service/sample-app-green-service 8080:80 -n $Namespace
}

function Invoke-Clean {
    Write-Host "Cleaning up resources..." -ForegroundColor Blue
    kubectl delete namespace $Namespace
}

function Invoke-Setup {
    Write-Host "Running complete setup..." -ForegroundColor Blue
    Invoke-Init
    Invoke-Apply
    Invoke-Build
    Invoke-Push
    Invoke-Deploy
}

function Invoke-All {
    Write-Host "Running complete setup and tests..." -ForegroundColor Blue
    Invoke-Setup
    Invoke-Test
}

# Main command dispatcher
switch ($Command.ToLower()) {
    "help" { Show-Help }
    "init" { Invoke-Init }
    "plan" { Invoke-Plan }
    "apply" { Invoke-Apply }
    "destroy" { Invoke-Destroy }
    "build" { Invoke-Build }
    "push" { Invoke-Push }
    "deploy" { Invoke-Deploy }
    "deploy-green" { Invoke-DeployGreen }
    "switch-to-green" { Invoke-SwitchToGreen }
    "switch-to-blue" { Invoke-SwitchToBlue }
    "test" { Invoke-Test }
    "test-blue-green" { Invoke-TestBlueGreen }
    "status" { Invoke-Status }
    "logs" { Invoke-Logs }
    "logs-green" { Invoke-LogsGreen }
    "port-forward" { Invoke-PortForward }
    "port-forward-green" { Invoke-PortForwardGreen }
    "clean" { Invoke-Clean }
    "setup" { Invoke-Setup }
    "all" { Invoke-All }
    default {
        Write-Host "Unknown command: $Command" -ForegroundColor Red
        Show-Help
    }
}
