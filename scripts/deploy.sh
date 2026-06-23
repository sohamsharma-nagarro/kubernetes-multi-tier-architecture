#!/bin/bash

set -e

echo "🚀 Deploying Multi-Tier Architecture to Kubernetes..."

NAMESPACE="multi-tier"
K8S_DIR="k8s"

# Create namespace
echo "📦 Creating namespace..."
kubectl apply -f $K8S_DIR/namespace.yaml

# Wait for namespace to be created
sleep 2

# Apply configurations and secrets
echo "🔐 Applying ConfigMaps and Secrets..."
kubectl apply -f $K8S_DIR/configmap.yaml
kubectl apply -f $K8S_DIR/secrets.yaml
kubectl apply -f $K8S_DIR/db-init-configmap.yaml

# Deploy database
echo "🗄️  Deploying PostgreSQL Database..."
kubectl apply -f $K8S_DIR/db-pvc.yaml
kubectl apply -f $K8S_DIR/db-deployment.yaml
kubectl apply -f $K8S_DIR/db-service.yaml

# Wait for database to be ready
echo "⏳ Waiting for database to be ready..."
kubectl wait --for=condition=ready pod -l app=postgres-db -n $NAMESPACE --timeout=300s 2>/dev/null || true
sleep 10

# Deploy API service
echo "🌐 Deploying API Service..."
kubectl apply -f $K8S_DIR/api-deployment.yaml
kubectl apply -f $K8S_DIR/api-service.yaml

# Wait for API to be ready
echo "⏳ Waiting for API service to be ready..."
kubectl wait --for=condition=ready pod -l app=api-service -n $NAMESPACE --timeout=300s 2>/dev/null || true
sleep 5

# Apply HPA
echo "📈 Applying Horizontal Pod Autoscaler..."
kubectl apply -f $K8S_DIR/api-hpa.yaml

# Apply Ingress
echo "🌍 Applying Ingress..."
kubectl apply -f $K8S_DIR/ingress.yaml

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📊 Checking deployment status..."
kubectl get pods -n $NAMESPACE
echo ""
echo "🔗 Services:"
kubectl get svc -n $NAMESPACE
echo ""
echo "📈 HPA Status:"
kubectl get hpa -n $NAMESPACE
echo ""
echo "🌍 Ingress:"
kubectl get ingress -n $NAMESPACE
echo ""
echo "✨ To access the API, use the INGRESS_IP from above:"
echo "   curl http://<INGRESS_IP>/api/records"
