# Makefile for GKE Blue-Green Deployment

.PHONY: help init plan apply destroy build push deploy test clean

# Variables
PROJECT_ID ?= $(shell gcloud config get-value project)
REGION ?= us-central1
ZONE ?= us-central1-a
CLUSTER_NAME ?= gke-cluster
APP_NAME ?= sample-app
NAMESPACE ?= blue-green-demo

help: ## Show this help message
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

init: ## Initialize Terraform
	terraform init

plan: ## Plan Terraform deployment
	terraform plan

apply: ## Apply Terraform configuration
	terraform apply

destroy: ## Destroy Terraform infrastructure
	terraform destroy

build: ## Build Docker image
	cd app && docker build -t gcr.io/$(PROJECT_ID)/$(APP_NAME):latest .
	docker tag gcr.io/$(PROJECT_ID)/$(APP_NAME):latest gcr.io/$(PROJECT_ID)/$(APP_NAME):blue
	docker tag gcr.io/$(PROJECT_ID)/$(APP_NAME):latest gcr.io/$(PROJECT_ID)/$(APP_NAME):green

push: ## Push Docker images to GCR
	docker push gcr.io/$(PROJECT_ID)/$(APP_NAME):latest
	docker push gcr.io/$(PROJECT_ID)/$(APP_NAME):blue
	docker push gcr.io/$(PROJECT_ID)/$(APP_NAME):green

deploy: ## Deploy application to GKE
	kubectl apply -f k8s/namespace.yaml
	kubectl apply -f k8s/blue-deployment.yaml
	kubectl apply -f k8s/hpa.yaml

deploy-green: ## Deploy green version
	kubectl apply -f k8s/green-deployment.yaml

switch-to-green: ## Switch traffic to green
	kubectl patch ingress sample-app-ingress -n $(NAMESPACE) -p '{"spec":{"rules":[{"host":"sample-app.example.com","http":{"paths":[{"path":"/","pathType":"Prefix","backend":{"service":{"name":"sample-app-green-service","port":{"number":80}}}}]}}]}}'
	kubectl patch hpa sample-app-hpa -n $(NAMESPACE) -p '{"spec":{"scaleTargetRef":{"name":"sample-app-green"}}}'

switch-to-blue: ## Switch traffic to blue
	kubectl patch ingress sample-app-ingress -n $(NAMESPACE) -p '{"spec":{"rules":[{"host":"sample-app.example.com","http":{"paths":[{"path":"/","pathType":"Prefix","backend":{"service":{"name":"sample-app-blue-service","port":{"number":80}}}}]}}]}}'
	kubectl patch hpa sample-app-hpa -n $(NAMESPACE) -p '{"spec":{"scaleTargetRef":{"name":"sample-app-blue"}}}'

test: ## Run tests
	./scripts/test-autoscaling.sh

test-blue-green: ## Test blue-green deployment
	./scripts/blue-green-deploy.sh

status: ## Show deployment status
	kubectl get all -n $(NAMESPACE)
	kubectl get hpa -n $(NAMESPACE)
	kubectl get ingress -n $(NAMESPACE)

logs: ## Show application logs
	kubectl logs -f deployment/sample-app-blue -n $(NAMESPACE)

logs-green: ## Show green deployment logs
	kubectl logs -f deployment/sample-app-green -n $(NAMESPACE)

port-forward: ## Port forward to blue service
	kubectl port-forward service/sample-app-blue-service 8080:80 -n $(NAMESPACE)

port-forward-green: ## Port forward to green service
	kubectl port-forward service/sample-app-green-service 8080:80 -n $(NAMESPACE)

clean: ## Clean up resources
	kubectl delete namespace $(NAMESPACE)

setup: init apply build push deploy ## Complete setup (init, apply, build, push, deploy)

all: setup test ## Complete setup and run tests
