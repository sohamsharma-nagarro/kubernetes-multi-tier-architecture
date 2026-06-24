#!/bin/bash

set -e

echo "🧹 Cleaning up Kubernetes resources..."

NAMESPACE="multi-tier"

# Delete namespace (this will delete all resources in it)
echo "Deleting namespace: $NAMESPACE"
kubectl delete namespace $NAMESPACE --ignore-not-found=true

echo "✅ Cleanup complete!"
