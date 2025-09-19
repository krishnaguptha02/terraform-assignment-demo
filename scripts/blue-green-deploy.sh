#!/bin/bash

# Blue-Green Deployment Script
# This script demonstrates blue-green deployment strategy

set -e

NAMESPACE="blue-green-demo"
PROJECT_ID="your-gcp-project-id"
APP_NAME="sample-app"

echo "Starting Blue-Green Deployment Demo..."

# Function to check deployment health
check_deployment_health() {
    local deployment_name=$1
    local namespace=$2
    
    echo "Checking health of deployment: $deployment_name"
    
    # Wait for deployment to be ready
    kubectl rollout status deployment/$deployment_name -n $namespace --timeout=300s
    
    # Check if all pods are ready
    local ready_pods=$(kubectl get deployment $deployment_name -n $namespace -o jsonpath='{.status.readyReplicas}')
    local desired_pods=$(kubectl get deployment $deployment_name -n $namespace -o jsonpath='{.spec.replicas}')
    
    if [ "$ready_pods" = "$desired_pods" ]; then
        echo "✅ Deployment $deployment_name is healthy ($ready_pods/$desired_pods pods ready)"
        return 0
    else
        echo "❌ Deployment $deployment_name is not healthy ($ready_pods/$desired_pods pods ready)"
        return 1
    fi
}

# Function to test service endpoint
test_service() {
    local service_name=$1
    local namespace=$2
    local expected_version=$3
    
    echo "Testing service: $service_name"
    
    # Port forward to service
    kubectl port-forward service/$service_name 8080:80 -n $namespace &
    PORT_FORWARD_PID=$!
    
    # Wait for port forward
    sleep 10
    
    # Test the endpoint
    local response=$(curl -s http://localhost:8080/version)
    local version=$(echo $response | jq -r '.version')
    
    if [ "$version" = "$expected_version" ]; then
        echo "✅ Service $service_name is serving version $version"
    else
        echo "❌ Service $service_name is serving version $version, expected $expected_version"
    fi
    
    # Clean up port forward
    kill $PORT_FORWARD_PID 2>/dev/null || true
}

# Step 1: Deploy Blue version
echo "Step 1: Deploying Blue version..."
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/blue-deployment.yaml

# Wait for blue deployment to be ready
check_deployment_health "sample-app-blue" $NAMESPACE

# Test blue service
test_service "sample-app-blue-service" $NAMESPACE "blue"

# Step 2: Deploy Green version
echo "Step 2: Deploying Green version..."
kubectl apply -f k8s/green-deployment.yaml

# Wait for green deployment to be ready
check_deployment_health "sample-app-green" $NAMESPACE

# Test green service
test_service "sample-app-green-service" $NAMESPACE "green"

# Step 3: Switch traffic to Green (Blue-Green switch)
echo "Step 3: Switching traffic to Green version..."

# Update ingress to point to green service
kubectl patch ingress sample-app-ingress -n $NAMESPACE -p '{"spec":{"rules":[{"host":"sample-app.example.com","http":{"paths":[{"path":"/","pathType":"Prefix","backend":{"service":{"name":"sample-app-green-service","port":{"number":80}}}}]}}]}}'

echo "Traffic switched to Green version"

# Wait a moment for the switch to take effect
sleep 30

# Step 4: Verify the switch
echo "Step 4: Verifying traffic switch..."

# Test the main endpoint (should now serve green)
test_service "sample-app-green-service" $NAMESPACE "green"

# Step 5: Update HPA to target green deployment
echo "Step 5: Updating HPA to target Green deployment..."
kubectl patch hpa sample-app-hpa -n $NAMESPACE -p '{"spec":{"scaleTargetRef":{"name":"sample-app-green"}}}'

echo "HPA updated to target Green deployment"

# Step 6: Clean up Blue deployment (optional)
read -p "Do you want to scale down the Blue deployment? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Scaling down Blue deployment..."
    kubectl scale deployment sample-app-blue --replicas=0 -n $NAMESPACE
    echo "Blue deployment scaled down"
fi

# Final status
echo "=== Final Deployment Status ==="
kubectl get deployments -n $NAMESPACE
kubectl get services -n $NAMESPACE
kubectl get ingress -n $NAMESPACE
kubectl get hpa -n $NAMESPACE

echo "Blue-Green deployment demo completed!"
