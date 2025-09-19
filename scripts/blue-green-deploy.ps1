# Blue-Green Deployment Script for Windows PowerShell
# This script demonstrates blue-green deployment strategy

param(
    [string]$Namespace = "blue-green-demo",
    [string]$ProjectId = "gke-blue-green-demo",
    [string]$AppName = "sample-app"
)

Write-Host "Starting Blue-Green Deployment Demo..." -ForegroundColor Blue

# Function to check deployment health
function Test-DeploymentHealth {
    param(
        [string]$DeploymentName,
        [string]$Namespace
    )
    
    Write-Host "Checking health of deployment: $DeploymentName" -ForegroundColor Yellow
    
    # Wait for deployment to be ready
    kubectl rollout status deployment/$DeploymentName -n $Namespace --timeout=300s
    
    # Check if all pods are ready
    $readyPods = kubectl get deployment $DeploymentName -n $Namespace -o jsonpath='{.status.readyReplicas}'
    $desiredPods = kubectl get deployment $DeploymentName -n $Namespace -o jsonpath='{.spec.replicas}'
    
    if ($readyPods -eq $desiredPods) {
        Write-Host "✅ Deployment $DeploymentName is healthy ($readyPods/$desiredPods pods ready)" -ForegroundColor Green
        return $true
    } else {
        Write-Host "❌ Deployment $DeploymentName is not healthy ($readyPods/$desiredPods pods ready)" -ForegroundColor Red
        return $false
    }
}

# Function to test service endpoint
function Test-ServiceEndpoint {
    param(
        [string]$ServiceName,
        [string]$Namespace,
        [string]$ExpectedVersion
    )
    
    Write-Host "Testing service: $ServiceName" -ForegroundColor Yellow
    
    # Start port forward
    $portForwardJob = Start-Job -ScriptBlock {
        param($ServiceName, $Namespace)
        kubectl port-forward service/$ServiceName 8080:80 -n $Namespace
    } -ArgumentList $ServiceName, $Namespace
    
    # Wait for port forward
    Start-Sleep -Seconds 10
    
    try {
        # Test the endpoint
        $response = Invoke-RestMethod -Uri "http://localhost:8080/version" -Method Get
        $version = $response.version
        
        if ($version -eq $ExpectedVersion) {
            Write-Host "✅ Service $ServiceName is serving version $version" -ForegroundColor Green
        } else {
            Write-Host "❌ Service $ServiceName is serving version $version, expected $ExpectedVersion" -ForegroundColor Red
        }
    } catch {
        Write-Host "❌ Failed to test service $ServiceName" -ForegroundColor Red
    } finally {
        # Clean up port forward
        $portForwardJob | Stop-Job
        $portForwardJob | Remove-Job
    }
}

# Step 1: Deploy Blue version
Write-Host "Step 1: Deploying Blue version..." -ForegroundColor Blue
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/blue-deployment.yaml

# Wait for blue deployment to be ready
if (Test-DeploymentHealth -DeploymentName "sample-app-blue" -Namespace $Namespace) {
    # Test blue service
    Test-ServiceEndpoint -ServiceName "sample-app-blue-service" -Namespace $Namespace -ExpectedVersion "blue"
} else {
    Write-Host "Blue deployment failed. Exiting." -ForegroundColor Red
    exit 1
}

# Step 2: Deploy Green version
Write-Host "Step 2: Deploying Green version..." -ForegroundColor Blue
kubectl apply -f k8s/green-deployment.yaml

# Wait for green deployment to be ready
if (Test-DeploymentHealth -DeploymentName "sample-app-green" -Namespace $Namespace) {
    # Test green service
    Test-ServiceEndpoint -ServiceName "sample-app-green-service" -Namespace $Namespace -ExpectedVersion "green"
} else {
    Write-Host "Green deployment failed. Exiting." -ForegroundColor Red
    exit 1
}

# Step 3: Switch traffic to Green (Blue-Green switch)
Write-Host "Step 3: Switching traffic to Green version..." -ForegroundColor Blue

# Update ingress to point to green service
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

Write-Host "Traffic switched to Green version" -ForegroundColor Green

# Wait a moment for the switch to take effect
Start-Sleep -Seconds 30

# Step 4: Verify the switch
Write-Host "Step 4: Verifying traffic switch..." -ForegroundColor Blue
Test-ServiceEndpoint -ServiceName "sample-app-green-service" -Namespace $Namespace -ExpectedVersion "green"

# Step 5: Update HPA to target green deployment
Write-Host "Step 5: Updating HPA to target Green deployment..." -ForegroundColor Blue
$hpaPatch = @{
    spec = @{
        scaleTargetRef = @{
            name = "sample-app-green"
        }
    }
} | ConvertTo-Json -Depth 5

kubectl patch hpa sample-app-hpa -n $Namespace -p $hpaPatch

Write-Host "HPA updated to target Green deployment" -ForegroundColor Green

# Step 6: Clean up Blue deployment (optional)
$cleanup = Read-Host "Do you want to scale down the Blue deployment? (y/n)"
if ($cleanup -eq "y" -or $cleanup -eq "Y") {
    Write-Host "Scaling down Blue deployment..." -ForegroundColor Yellow
    kubectl scale deployment sample-app-blue --replicas=0 -n $Namespace
    Write-Host "Blue deployment scaled down" -ForegroundColor Green
}

# Final status
Write-Host "=== Final Deployment Status ===" -ForegroundColor Cyan
kubectl get deployments -n $Namespace
kubectl get services -n $Namespace
kubectl get ingress -n $Namespace
kubectl get hpa -n $Namespace

Write-Host "Blue-Green deployment demo completed!" -ForegroundColor Green
