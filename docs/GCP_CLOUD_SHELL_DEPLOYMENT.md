# GCP Cloud Shell Deployment Guide

This guide provides step-by-step instructions to deploy the multi-tier Kubernetes architecture in Google Cloud Platform (GCP) using Cloud Shell.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Phase 1: Setup](#phase-1-setup)
3. [Phase 2: Create GKE Cluster](#phase-2-create-gke-cluster)
4. [Phase 3: Prepare Docker Hub Image](#phase-3-prepare-docker-hub-image)
5. [Phase 4: Deploy Application](#phase-4-deploy-application)
6. [Phase 5: Verify Deployment](#phase-5-verify-deployment)
7. [Phase 6: Test the Application](#phase-6-test-the-application)
8. [Phase 7: Cleanup](#phase-7-cleanup)

## Prerequisites

Before starting, ensure you have:

- **GCP Account**: Active Google Cloud Platform account with billing enabled
- **Internet Access**: Stable internet connection for Cloud Shell
- **Docker Hub Account** (Optional): For pushing custom images (or use pre-built image: `sohamsharma/py-api-service:latest`)

## Phase 1: Setup

### Step 1: Access Google Cloud Console

1. Navigate to [Google Cloud Console](https://console.cloud.google.com)
2. Log in with your GCP account
3. Click on the **Cloud Shell** icon (>_) in the top-right toolbar

   ![Cloud Shell Icon](https://cloud.google.com/shell/docs/images/shell-icon.png)

### Step 2: Verify Cloud Shell is Ready

```bash
# Cloud Shell should open at the bottom. Verify gcloud is configured
gcloud --version

# Should output something like: Google Cloud SDK 434.0.0
```

### Step 3: Clone the Repository

```bash
# Clone the repository
git clone https://github.com/sohamsharma-nagarro/kubernetes-multi-tier-architecture.git

# Navigate to the project directory
cd kubernetes-multi-tier-architecture

# Verify directory structure
ls -la
```

Expected output:
```
api/               - Flask API application
database/          - Database initialization scripts
docker-compose.yaml
docs/              - Documentation files
k8s/               - Kubernetes manifests
scripts/           - Deployment scripts
README.md
```

### Step 4: Set GCP Project and Variables

```bash
# Set your GCP project ID (replace YOUR_PROJECT_ID)
export PROJECT_ID="your-project-id"
export GCP_REGION="us-central1"
export GCP_ZONE="us-central1-a"
export CLUSTER_NAME="multi-tier-cluster"

# Configure gcloud to use your project
gcloud config set project $PROJECT_ID

# Verify the project is set
gcloud config get-value project
```

## Phase 2: Create GKE Cluster

### Step 1: Enable Required APIs

```bash
echo "Enabling required GCP APIs..."

# Enable Kubernetes Engine API
gcloud services enable container.googleapis.com

# Enable Compute Engine API
gcloud services enable compute.googleapis.com

# Enable Cloud Build API (optional, for building images)
gcloud services enable cloudbuild.googleapis.com

echo "✅ APIs enabled successfully"
```

### Step 2: Create GKE Cluster

```bash
echo "🚀 Creating GKE cluster: $CLUSTER_NAME"

gcloud container clusters create $CLUSTER_NAME \
  --zone $GCP_ZONE \
  --num-nodes 3 \
  --machine-type n1-standard-2 \
  --enable-autoscaling \
  --min-nodes 3 \
  --max-nodes 5 \
  --enable-stackdriver-kubernetes \
  --addons HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver \
  --workload-pool=$PROJECT_ID.svc.id.goog \
  --enable-ip-alias \
  --network "default"

echo "⏳ Cluster creation in progress. This may take 5-10 minutes..."
```

**Note**: If you encounter quota errors, you may need to:
- Increase your GCP quota
- Use smaller machine types (e.g., `n1-standard-1`)
- Reduce the number of nodes to 2

### Step 3: Get Cluster Credentials

Once the cluster is created, configure kubectl:

```bash
# Get cluster credentials
gcloud container clusters get-credentials $CLUSTER_NAME --zone $GCP_ZONE

# Verify kubectl can access the cluster
kubectl cluster-info

# Should show cluster information
```

### Step 4: Verify Node Status

```bash
# Check that all nodes are ready
kubectl get nodes

# Expected output: 3 nodes with status "Ready"
```

## Phase 3: Prepare Docker Hub Image

### Option A: Use Pre-Built Image (Recommended for Quick Start)

The repository uses a pre-built image: `sohamsharma/py-api-service:latest`

```bash
# Verify the image exists (this will be pulled during deployment)
echo "Using pre-built image: sohamsharma/py-api-service:latest"
```

### Option B: Build and Push Your Own Image

If you want to build and push your own image:

#### Step 1: Set Docker Hub Credentials

```bash
# Set your Docker Hub username
export DOCKER_HUB_USERNAME="your-docker-hub-username"

# Login to Docker Hub
docker login -u $DOCKER_HUB_USERNAME

# When prompted, enter your Docker Hub password or personal access token
```

#### Step 2: Make Script Executable and Build Image

```bash
# Make the push script executable
chmod +x scripts/push-docker-hub.sh

# Build and push the image
./scripts/push-docker-hub.sh $DOCKER_HUB_USERNAME latest

# This script will:
# - Build the Flask API Docker image
# - Tag it as YOUR_USERNAME/py-api-service:latest
# - Push it to Docker Hub
```

#### Step 3: Update Kubernetes Deployment (if using custom image)

```bash
# Edit the api-deployment.yaml to use your image
sed -i "s|sohamsharma/py-api-service:latest|$DOCKER_HUB_USERNAME/py-api-service:latest|g" k8s/api-deployment.yaml

# Verify the change
grep "image:" k8s/api-deployment.yaml
```

## Phase 4: Deploy Application

### Step 1: Make Deployment Scripts Executable

```bash
# Make all scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/verify.sh
chmod +x scripts/test-api.sh
chmod +x scripts/cleanup.sh
```

### Step 2: Deploy All Resources

```bash
echo "🚀 Deploying multi-tier architecture to GKE..."

# Run the deployment script
./scripts/deploy.sh

# The script will:
# - Create multi-tier namespace
# - Deploy ConfigMaps and Secrets
# - Deploy PostgreSQL database
# - Deploy Flask API service with 4 replicas
# - Configure HPA (Horizontal Pod Autoscaler)
# - Set up Ingress for external access
```

### Step 3: Monitor Deployment Progress

```bash
# Watch the deployment progress
echo "Waiting for deployments to be ready..."

# Monitor database deployment
kubectl rollout status deployment/postgres-db -n multi-tier

# Monitor API service deployment
kubectl rollout status deployment/api-service -n multi-tier

# Check pod status
kubectl get pods -n multi-tier

# Expected: All pods should show "Running" status
```

### Step 4: View All Deployed Resources

```bash
# View all resources in the multi-tier namespace
kubectl get all -n multi-tier

# Expected output:
# - 1 postgres-db pod (Running)
# - 4 api-service pods (Running)
# - 2 services (postgres-db, api-service)
# - 1 ingress (api-ingress)
```

## Phase 5: Verify Deployment

### Step 1: Run Verification Script

```bash
# Run comprehensive verification
./scripts/verify.sh

# This will verify:
# ✅ Kubernetes cluster access
# ✅ Namespace and resources created
# ✅ ConfigMaps and Secrets configured
# ✅ Database pod is healthy
# ✅ API pods are healthy
# ✅ Services are properly exposed
# ✅ HPA is configured
# ✅ Ingress is set up
```

### Step 2: Check Resource Status Manually

```bash
# Get namespace details
kubectl get namespace multi-tier

# Get ConfigMaps
kubectl get configmap -n multi-tier

# Get Secrets
kubectl get secrets -n multi-tier

# Get PersistentVolumeClaim
kubectl get pvc -n multi-tier

# Get Deployments
kubectl get deployments -n multi-tier
```

### Step 3: View Pod Logs

```bash
# View API service logs
kubectl logs -n multi-tier deployment/api-service

# View database logs
kubectl logs -n multi-tier deployment/postgres-db

# View logs from a specific pod
POD_NAME=$(kubectl get pods -n multi-tier -l app=api-service -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n multi-tier $POD_NAME
```

## Phase 6: Test the Application

### Step 1: Get the Ingress IP Address

```bash
# Get the external IP of the Ingress
echo "Waiting for Ingress IP to be assigned..."

# Keep checking until IP is assigned (may take 2-5 minutes)
kubectl get ingress -n multi-tier

# Once IP is assigned, capture it
INGRESS_IP=$(kubectl get ingress -n multi-tier api-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Ingress IP: $INGRESS_IP"

# If IP shows as <pending>, wait a moment and try again
if [ -z "$INGRESS_IP" ]; then
  echo "⏳ IP still pending. Waiting 30 seconds..."
  sleep 30
  INGRESS_IP=$(kubectl get ingress -n multi-tier api-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  echo "Ingress IP: $INGRESS_IP"
fi
```

### Step 2: Test API Endpoints

```bash
# Test health endpoint
curl http://$INGRESS_IP/health

# Test readiness endpoint
curl http://$INGRESS_IP/ready

# Get all records
curl http://$INGRESS_IP/api/records

# Get specific record by ID
curl http://$INGRESS_IP/api/records/1

# Get health info
curl http://$INGRESS_IP/api/health-info
```

### Step 3: Run Automated API Tests

```bash
# Run the test script
./scripts/test-api.sh

# If test-api.sh requires the API URL, you can modify it:
# Edit scripts/test-api.sh and set API_URL="http://$INGRESS_IP"
# Or run tests manually with curl commands above
```

### Step 4: Expected API Responses

**GET /api/records** (Get all employee records)
```json
[
  {
    "id": 1,
    "name": "John Doe",
    "email": "john@example.com",
    "department": "Engineering"
  },
  ...
]
```

**GET /api/records/1** (Get specific record)
```json
{
  "id": 1,
  "name": "John Doe",
  "email": "john@example.com",
  "department": "Engineering"
}
```

**GET /health** (Liveness probe)
```json
{
  "status": "healthy"
}
```

**GET /ready** (Readiness probe)
```json
{
  "status": "ready"
}
```

## Phase 7: Advanced Operations

### Access Database from Cloud Shell

```bash
# Port-forward to the database
kubectl port-forward -n multi-tier service/postgres-db 5432:5432 &

# Install psql client (if not available)
apt-get update && apt-get install -y postgresql-client

# Connect to database
PGPASSWORD=$(kubectl get secret -n multi-tier db-secret -o jsonpath='{.data.password}' | base64 -d)
psql -h localhost -U postgres -d employee_db

# List tables
\dt

# Query employee records
SELECT * FROM employees;

# Exit psql
\q

# Kill the port-forward
jobs
kill %1
```

### Monitor with Kubernetes Dashboard

```bash
# Start kubectl proxy
kubectl proxy --port=8080 &

# Access dashboard in Cloud Shell's Web Preview
# Click on the Web Preview button and select port 8080
# Navigate to: http://localhost:8080/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```

### Monitor HPA (Horizontal Pod Autoscaling)

```bash
# Watch HPA status
kubectl get hpa -n multi-tier -w

# Check HPA details
kubectl describe hpa api-hpa -n multi-tier

# Generate load to test scaling (run in a separate Cloud Shell tab)
INGRESS_IP=$(kubectl get ingress -n multi-tier api-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
while true; do curl http://$INGRESS_IP/api/records; done
```

### Test Self-Healing

```bash
# Delete a pod to verify it auto-restarts
POD_NAME=$(kubectl get pods -n multi-tier -l app=api-service -o jsonpath='{.items[0].metadata.name}')
echo "Deleting pod: $POD_NAME"
kubectl delete pod -n multi-tier $POD_NAME

# Watch the pod being recreated
kubectl get pods -n multi-tier -w

# The pod should restart automatically within 30 seconds
```

### View Real-Time Metrics

```bash
# Get current resource usage
kubectl top nodes
kubectl top pods -n multi-tier

# Note: Metrics may take a few minutes to appear after deployment
```

## Phase 8: Cleanup

### Step 1: Delete GKE Cluster

```bash
# WARNING: This will delete all resources and cannot be undone!

echo "Deleting GKE cluster: $CLUSTER_NAME"

gcloud container clusters delete $CLUSTER_NAME \
  --zone $GCP_ZONE \
  --quiet

# Alternatively, run the cleanup script to remove Kubernetes resources only:
./scripts/cleanup.sh

# This will delete only the Kubernetes resources, not the GCP cluster
```

### Step 2: Clean Up Other Resources

```bash
# Delete persistent disks if needed (they may persist after cluster deletion)
gcloud compute disks list --zones=$GCP_ZONE

# Delete a specific disk
gcloud compute disks delete <disk-name> --zone=$GCP_ZONE --quiet

# Delete external IP addresses if any are unattached
gcloud compute addresses list

# Release addresses
gcloud compute addresses delete <address-name> --region=us-central1 --quiet
```

## Troubleshooting

### Issue: Cloud Shell Session Timeout

**Problem**: Cloud Shell disconnects after 20 minutes of inactivity

**Solution**: 
- Keep your session active or reconnect
- For long-running deployments, consider using Google Cloud Console directly

### Issue: Cluster Creation Fails with Quota Error

**Problem**: Error message mentions quota or resource limits

**Solutions**:
- Use a smaller machine type: `n1-standard-1` instead of `n1-standard-2`
- Reduce the number of nodes: `--num-nodes 2` instead of 3
- Check your GCP quota: Go to Console > APIs & Services > Quotas

### Issue: Ingress IP Shows `<pending>`

**Problem**: `kubectl get ingress` shows `<pending>` for IP

**Solutions**:
- Wait 3-5 minutes for the load balancer to be provisioned
- Check ingress status: `kubectl describe ingress -n multi-tier api-ingress`
- Verify the ingress controller is running: `kubectl get pods -n kube-system | grep ingress`

### Issue: Pods Stuck in `Pending` State

**Problem**: Pods don't transition to `Running`

**Solutions**:
```bash
# Check pod events
kubectl describe pod <pod-name> -n multi-tier

# Check node status
kubectl describe nodes

# Check resource requests vs available resources
kubectl top nodes
```

### Issue: API Returns 502 Bad Gateway

**Problem**: Ingress returns 502 error

**Solutions**:
- Verify API pods are running: `kubectl get pods -n multi-tier`
- Check API pod logs: `kubectl logs -n multi-tier deployment/api-service`
- Verify database connectivity: Check database pod logs
- Wait a bit longer for pods to become ready

### Issue: Cannot Pull Docker Image

**Problem**: ImagePullBackOff error

**Solutions**:
- Verify the image exists and is public
- For private images, create ImagePullSecret:
```bash
kubectl create secret docker-registry regcred \
  --docker-server=docker.io \
  --docker-username=YOUR_USERNAME \
  --docker-****** \
  -n multi-tier
```

## Cost Optimization Tips

1. **Use Preemptible Nodes**: Add `--preemptible` flag to cluster creation (50-80% savings)
2. **Configure Cluster Autoscaling**: Already enabled with `--enable-autoscaling`
3. **Use Reserved Instances**: For stable workloads, use Google Cloud's committed use discounts
4. **Monitor Costs**: Use GCP Cost Analysis in Cloud Console
5. **Clean Up**: Delete unused clusters and persistent disks

## Additional Resources

- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [Cloud Shell Documentation](https://cloud.google.com/shell/docs)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Project README](../README.md)
- [FINOPS Strategy](./FINOPS.md)
- [Architecture Overview](./SOLUTION_OVERVIEW.md)

## Quick Reference Commands

```bash
# Setup
gcloud config set project YOUR_PROJECT_ID
gcloud container clusters create multi-tier-cluster --zone us-central1-a --num-nodes 3 --machine-type n1-standard-2
gcloud container clusters get-credentials multi-tier-cluster --zone us-central1-a

# Deploy
./scripts/deploy.sh

# Verify
./scripts/verify.sh

# Get Ingress IP
kubectl get ingress -n multi-tier

# Test API
curl http://INGRESS_IP/api/records

# Cleanup
gcloud container clusters delete multi-tier-cluster --zone us-central1-a --quiet
```

---

**Last Updated**: 2026-06-24  
**Author**: Kubernetes Multi-Tier Architecture Project
