pipeline {
    agent any
    
    environment {
        GCP_PROJECT_ID = 'your-gcp-project-id'
        GKE_CLUSTER_NAME = 'gke-cluster'
        GKE_ZONE = 'us-central1-a'
        GCR_REGISTRY = "gcr.io/${GCP_PROJECT_ID}"
        APP_NAME = 'sample-app'
        NAMESPACE = 'blue-green-demo'
    }
    
    parameters {
        choice(
            name: 'DEPLOYMENT_STRATEGY',
            choices: ['blue', 'green'],
            description: 'Choose deployment strategy (blue or green)'
        )
        string(
            name: 'APP_VERSION',
            defaultValue: '1.0.0',
            description: 'Application version to deploy'
        )
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Build Docker Image') {
            steps {
                script {
                    def imageTag = "${params.DEPLOYMENT_STRATEGY}-${params.APP_VERSION}-${env.BUILD_NUMBER}"
                    def imageName = "${GCR_REGISTRY}/${APP_NAME}:${imageTag}"
                    
                    echo "Building Docker image: ${imageName}"
                    
                    dir('app') {
                        sh """
                            docker build -t ${imageName} .
                            docker tag ${imageName} ${GCR_REGISTRY}/${APP_NAME}:${params.DEPLOYMENT_STRATEGY}
                        """
                    }
                }
            }
        }
        
        stage('Push to GCR') {
            steps {
                script {
                    def imageTag = "${params.DEPLOYMENT_STRATEGY}-${params.APP_VERSION}-${env.BUILD_NUMBER}"
                    def imageName = "${GCR_REGISTRY}/${APP_NAME}:${imageTag}"
                    
                    echo "Pushing Docker image to GCR: ${imageName}"
                    
                    sh """
                        gcloud auth configure-docker
                        docker push ${imageName}
                        docker push ${GCR_REGISTRY}/${APP_NAME}:${params.DEPLOYMENT_STRATEGY}
                    """
                }
            }
        }
        
        stage('Deploy to GKE') {
            steps {
                script {
                    echo "Deploying to GKE cluster: ${GKE_CLUSTER_NAME}"
                    
                    sh """
                        gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} --zone ${GKE_ZONE} --project ${GCP_PROJECT_ID}
                        
                        # Update the deployment with the new image
                        sed -i 's|gcr.io/PROJECT_ID/sample-app:${params.DEPLOYMENT_STRATEGY}|${GCR_REGISTRY}/${APP_NAME}:${params.DEPLOYMENT_STRATEGY}|g' k8s/${params.DEPLOYMENT_STRATEGY}-deployment.yaml
                        
                        # Apply the deployment
                        kubectl apply -f k8s/namespace.yaml
                        kubectl apply -f k8s/${params.DEPLOYMENT_STRATEGY}-deployment.yaml
                        
                        # Wait for deployment to be ready
                        kubectl rollout status deployment/sample-app-${params.DEPLOYMENT_STRATEGY} -n ${NAMESPACE} --timeout=300s
                    """
                }
            }
        }
        
        stage('Blue-Green Switch') {
            when {
                expression { params.DEPLOYMENT_STRATEGY == 'green' }
            }
            steps {
                script {
                    echo "Performing blue-green switch..."
                    
                    sh """
                        # Update ingress to point to green service
                        kubectl patch ingress sample-app-ingress -n ${NAMESPACE} -p '{"spec":{"rules":[{"host":"sample-app.example.com","http":{"paths":[{"path":"/","pathType":"Prefix","backend":{"service":{"name":"sample-app-green-service","port":{"number":80}}}}]}}]}}'
                        
                        # Wait for ingress to be updated
                        sleep 30
                        
                        # Verify green deployment is healthy
                        kubectl get pods -n ${NAMESPACE} -l version=green
                        
                        # Update HPA to target green deployment
                        kubectl patch hpa sample-app-hpa -n ${NAMESPACE} -p '{"spec":{"scaleTargetRef":{"name":"sample-app-green"}}}'
                        
                        echo "Blue-green switch completed. Green deployment is now live."
                    """
                }
            }
        }
        
        stage('Health Check') {
            steps {
                script {
                    echo "Performing health check..."
                    
                    sh """
                        # Get the service endpoint
                        kubectl get service sample-app-${params.DEPLOYMENT_STRATEGY}-service -n ${NAMESPACE}
                        
                        # Port forward for testing
                        kubectl port-forward service/sample-app-${params.DEPLOYMENT_STRATEGY}-service 8080:80 -n ${NAMESPACE} &
                        sleep 10
                        
                        # Test health endpoint
                        curl -f http://localhost:8080/health || exit 1
                        curl -f http://localhost:8080/ || exit 1
                        
                        # Kill port forward
                        pkill -f "kubectl port-forward"
                    """
                }
            }
        }
        
        stage('Cleanup Old Deployment') {
            when {
                expression { params.DEPLOYMENT_STRATEGY == 'green' }
            }
            steps {
                script {
                    echo "Cleaning up old blue deployment..."
                    
                    sh """
                        # Scale down blue deployment
                        kubectl scale deployment sample-app-blue --replicas=0 -n ${NAMESPACE}
                        
                        echo "Old blue deployment scaled down."
                    """
                }
            }
        }
    }
    
    post {
        always {
            echo "Pipeline completed for ${params.DEPLOYMENT_STRATEGY} deployment"
        }
        success {
            echo "Deployment successful!"
        }
        failure {
            echo "Deployment failed!"
        }
    }
}
