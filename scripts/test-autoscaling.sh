#!/bin/bash

# Test Auto-scaling Script
# This script generates load to test the HPA (Horizontal Pod Autoscaler)

set -e

NAMESPACE="blue-green-demo"
SERVICE_NAME="sample-app-blue-service"
LOAD_DURATION=300  # 5 minutes
CONCURRENT_REQUESTS=50

echo "Starting auto-scaling test..."
echo "Namespace: $NAMESPACE"
echo "Service: $SERVICE_NAME"
echo "Load duration: $LOAD_DURATION seconds"
echo "Concurrent requests: $CONCURRENT_REQUESTS"

# Get the service endpoint
echo "Getting service endpoint..."
kubectl port-forward service/$SERVICE_NAME 8080:80 -n $NAMESPACE &
PORT_FORWARD_PID=$!

# Wait for port forward to be ready
sleep 10

# Function to generate load
generate_load() {
    local duration=$1
    local concurrent=$2
    
    echo "Generating load for $duration seconds with $concurrent concurrent requests..."
    
    # Use curl to generate load
    for i in $(seq 1 $concurrent); do
        (
            while [ $(date +%s) -lt $(( $(date +%s) + duration )) ]; do
                curl -s http://localhost:8080/load > /dev/null
                sleep 0.1
            done
        ) &
    done
    
    wait
}

# Monitor HPA and pods
monitor_scaling() {
    echo "Monitoring HPA and pod scaling..."
    
    while [ $(date +%s) -lt $(( $(date +%s) + LOAD_DURATION )) ]; do
        echo "=== $(date) ==="
        echo "HPA Status:"
        kubectl get hpa -n $NAMESPACE
        echo ""
        echo "Pod Status:"
        kubectl get pods -n $NAMESPACE -l app=sample-app
        echo ""
        echo "Node Status:"
        kubectl get nodes
        echo ""
        sleep 30
    done
}

# Start monitoring in background
monitor_scaling &
MONITOR_PID=$!

# Generate load
generate_load $LOAD_DURATION $CONCURRENT_REQUESTS

# Wait for monitoring to complete
wait $MONITOR_PID

# Clean up
kill $PORT_FORWARD_PID 2>/dev/null || true

echo "Auto-scaling test completed!"
echo "Final HPA status:"
kubectl get hpa -n $NAMESPACE
echo ""
echo "Final pod status:"
kubectl get pods -n $NAMESPACE -l app=sample-app
