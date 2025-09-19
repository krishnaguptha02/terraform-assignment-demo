# Test Auto-scaling Script for Windows PowerShell
# This script generates load to test the HPA (Horizontal Pod Autoscaler)

param(
    [string]$Namespace = "blue-green-demo",
    [string]$ServiceName = "sample-app-blue-service",
    [int]$LoadDuration = 300,  # 5 minutes
    [int]$ConcurrentRequests = 50
)

Write-Host "Starting auto-scaling test..." -ForegroundColor Blue
Write-Host "Namespace: $Namespace" -ForegroundColor Green
Write-Host "Service: $ServiceName" -ForegroundColor Green
Write-Host "Load duration: $LoadDuration seconds" -ForegroundColor Green
Write-Host "Concurrent requests: $ConcurrentRequests" -ForegroundColor Green

# Function to generate load
function Generate-Load {
    param(
        [int]$Duration,
        [int]$Concurrent
    )
    
    Write-Host "Generating load for $Duration seconds with $Concurrent concurrent requests..." -ForegroundColor Yellow
    
    $jobs = @()
    
    for ($i = 1; $i -le $Concurrent; $i++) {
        $job = Start-Job -ScriptBlock {
            param($Duration)
            $endTime = (Get-Date).AddSeconds($Duration)
            while ((Get-Date) -lt $endTime) {
                try {
                    Invoke-RestMethod -Uri "http://localhost:8080/load" -Method Get -TimeoutSec 5
                } catch {
                    # Ignore errors for load testing
                }
                Start-Sleep -Milliseconds 100
            }
        } -ArgumentList $Duration
        $jobs += $job
    }
    
    # Wait for all jobs to complete
    $jobs | Wait-Job | Out-Null
    $jobs | Remove-Job
}

# Function to monitor scaling
function Monitor-Scaling {
    param(
        [int]$Duration
    )
    
    Write-Host "Monitoring HPA and pod scaling..." -ForegroundColor Blue
    
    $endTime = (Get-Date).AddSeconds($Duration)
    
    while ((Get-Date) -lt $endTime) {
        Write-Host "=== $(Get-Date) ===" -ForegroundColor Cyan
        Write-Host "HPA Status:" -ForegroundColor Yellow
        kubectl get hpa -n $Namespace
        Write-Host ""
        Write-Host "Pod Status:" -ForegroundColor Yellow
        kubectl get pods -n $Namespace -l app=sample-app
        Write-Host ""
        Write-Host "Node Status:" -ForegroundColor Yellow
        kubectl get nodes
        Write-Host ""
        Start-Sleep -Seconds 30
    }
}

# Start port forwarding
Write-Host "Starting port forward..." -ForegroundColor Blue
$portForwardJob = Start-Job -ScriptBlock {
    kubectl port-forward service/sample-app-blue-service 8080:80 -n blue-green-demo
}

# Wait for port forward to be ready
Start-Sleep -Seconds 10

# Start monitoring in background
$monitorJob = Start-Job -ScriptBlock {
    param($Namespace, $Duration)
    $endTime = (Get-Date).AddSeconds($Duration)
    
    while ((Get-Date) -lt $endTime) {
        Write-Host "=== $(Get-Date) ===" -ForegroundColor Cyan
        Write-Host "HPA Status:" -ForegroundColor Yellow
        kubectl get hpa -n $Namespace
        Write-Host ""
        Write-Host "Pod Status:" -ForegroundColor Yellow
        kubectl get pods -n $Namespace -l app=sample-app
        Write-Host ""
        Write-Host "Node Status:" -ForegroundColor Yellow
        kubectl get nodes
        Write-Host ""
        Start-Sleep -Seconds 30
    }
} -ArgumentList $Namespace, $LoadDuration

# Generate load
Generate-Load -Duration $LoadDuration -Concurrent $ConcurrentRequests

# Wait for monitoring to complete
$monitorJob | Wait-Job | Out-Null

# Clean up
$portForwardJob | Stop-Job
$portForwardJob | Remove-Job
$monitorJob | Remove-Job

Write-Host "Auto-scaling test completed!" -ForegroundColor Green
Write-Host "Final HPA status:" -ForegroundColor Yellow
kubectl get hpa -n $Namespace
Write-Host ""
Write-Host "Final pod status:" -ForegroundColor Yellow
kubectl get pods -n $Namespace -l app=sample-app
