# Cloud SQL Deployment Guide for GKE

This guide provides comprehensive instructions for deploying the multi-tier microservices architecture to Google Kubernetes Engine (GKE) using Cloud SQL (managed PostgreSQL) instead of in-cluster PostgreSQL.

**Benefits of using Cloud SQL:**
- ✅ **Managed Service**: Google handles backups, replication, and maintenance
- ✅ **High Availability**: Automatic failover with multi-zone instances
- ✅ **Private IP**: Secure communication within VPC without exposing to internet
- ✅ **Scalability**: Easier to scale database without affecting Kubernetes cluster
- ✅ **Compliance**: Meets enterprise security and regulatory requirements
- ✅ **Cost-Efficient**: Pay for database separately from compute resources

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start](#quick-start)
3. [Manual Step-by-Step Setup](#manual-step-by-step-setup)
4. [Verification](#verification)
5. [Monitoring](#monitoring)
6. [Troubleshooting](#troubleshooting)
7. [Security Best Practices](#security-best-practices)
8. [Cleanup](#cleanup)

## Prerequisites

### Required Tools
- **gcloud CLI**: [Install](https://cloud.google.com/sdk/docs/install)
- **kubectl**: Installed with gcloud SDK
- **Active GCP Project**: With billing enabled
- **Service Account**: With appropriate IAM roles

### Required IAM Roles
- `roles/container.admin`
- `roles/cloudsql.admin`
- `roles/iam.serviceAccountAdmin`
- `roles/servicemanagement.admin`

### Environment Variables Template

Create a `.env` file or export these variables:

```bash
# GCP Project and Region Configuration
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# GKE Cluster Configuration
export CLUSTER="api-cluster"
export VPC_NAME="default"
export SUBNET="default"

# Cloud SQL Configuration
export INSTANCE_NAME="my-sql-instance"
export DB_NAME="microservices_db"
export DB_USER="dbuser"
export DB_PASS='SecurePassword123!@#'  # Change this!

# Kubernetes Configuration
export NAMESPACE="multi-tier"
export SERVICE_ACCOUNT_NAME="api-k8s-sa"
export IMAGE_TAG="latest"
```

## Quick Start

### Using the Automated Deployment Script

The easiest way to deploy is using the provided automation script:

```bash
# 1. Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export CLUSTER="api-cluster"
export INSTANCE_NAME="my-sql-instance"
export DB_NAME="microservices_db"
export DB_USER="dbuser"
export DB_PASS='SecurePassword123!@#'
export NAMESPACE="multi-tier"
export SERVICE_ACCOUNT_NAME="api-k8s-sa"

# 2. Run the deployment script
chmod +x scripts/deploy-cloud-sql.sh
./scripts/deploy-cloud-sql.sh
```

The script will:
1. ✅ Enable required Google Cloud APIs
2. ✅ Create a VPC-native GKE cluster
3. ✅ Create a Cloud SQL instance with Private IP
4. ✅ Initialize the database and user
5. ✅ Create Kubernetes secrets and ConfigMaps
6. ✅ Deploy the API service
7. ✅ Configure autoscaling and ingress

## Manual Step-by-Step Setup

If you prefer to set up manually or need to troubleshoot, follow these steps:

### Step 1: Enable Google Cloud APIs

```bash
gcloud services enable \
  container.googleapis.com \
  sqladmin.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  iam.googleapis.com \
  --project=$PROJECT_ID
```

### Step 2: Create a VPC-Native GKE Cluster

```bash
gcloud container clusters create $CLUSTER \
  --zone $ZONE \
  --num-nodes=2 \
  --enable-ip-alias \
  --network=$VPC_NAME \
  --subnetwork=$SUBNET \
  --machine-type=n1-standard-2 \
  --enable-autoscaling \
  --min-nodes=2 \
  --max-nodes=5 \
  --project=$PROJECT_ID
```

Get cluster credentials:

```bash
gcloud container clusters get-credentials $CLUSTER \
  --zone $ZONE \
  --project=$PROJECT_ID
```

### Step 3: Create Cloud SQL Instance with Private IP

Create the instance:

```bash
gcloud sql instances create $INSTANCE_NAME \
  --database-version=POSTGRES_15 \
  --region=$REGION \
  --network=projects/${PROJECT_ID}/global/networks/${VPC_NAME} \
  --no-assign-ip \
  --tier=db-f1-micro \
  --project=$PROJECT_ID
```

This creates a PostgreSQL 15 instance with:
- **Private IP only** (no public IP)
- **VPC-native networking** for secure communication
- **Automatic backups** enabled by default

### Step 4: Create Database and User

Create the database:

```bash
gcloud sql databases create $DB_NAME \
  --instance=$INSTANCE_NAME \
  --project=$PROJECT_ID
```

Create/update the database user:

```bash
gcloud sql users set-password $DB_USER \
  --instance=$INSTANCE_NAME \
  --****** \
  --project=$PROJECT_ID
```

### Step 5: Retrieve Cloud SQL Private IP

```bash
DB_HOST=$(gcloud sql instances describe $INSTANCE_NAME \
  --format="value(ipAddresses[0].ipAddress)" \
  --project=$PROJECT_ID)

echo "Cloud SQL Private IP: $DB_HOST"
```

### Step 6: Create Kubernetes Namespace

```bash
kubectl create namespace $NAMESPACE
```

### Step 7: Create Kubernetes Secrets

```bash
kubectl create secret generic db-credentials \
  -n $NAMESPACE \
  --from-literal=DB_HOST="$DB_HOST" \
  --from-literal=DB_PORT="5432" \
  --from-literal=DB_NAME="$DB_NAME" \
  --from-literal=DB_USER="$DB_USER" \
  --from-literal=DB_PASSWORD="$DB_PASS"
```

### Step 8: Create Kubernetes Service Account (Optional but Recommended)

```bash
kubectl create serviceaccount $SERVICE_ACCOUNT_NAME -n $NAMESPACE
```

### Step 9: Apply Kubernetes Manifests

Using the Cloud SQL manifests:

```bash
# Apply namespace
kubectl apply -f k8s-cloud-sql/namespace.yaml

# Apply configuration
kubectl apply -f k8s-cloud-sql/configmap.yaml
kubectl apply -f k8s-cloud-sql/secrets.yaml

# Deploy API service
kubectl apply -f k8s-cloud-sql/api-deployment.yaml
kubectl apply -f k8s-cloud-sql/api-service.yaml

# Apply autoscaling
kubectl apply -f k8s-cloud-sql/api-hpa.yaml

# Apply ingress
kubectl apply -f k8s-cloud-sql/ingress.yaml
```

Or use the original `k8s/` manifests if they're updated with Cloud SQL credentials.

## Verification

### 1. Check Cluster Status

```bash
kubectl get nodes
kubectl get namespaces
```

### 2. Verify Cloud SQL Instance

```bash
gcloud sql instances describe $INSTANCE_NAME \
  --format="table(name, status, databaseVersion, ipAddresses[0].ipAddress)" \
  --project=$PROJECT_ID
```

Expected output:
```
NAME                          STATUS    VERSION          IP_ADDRESS
my-sql-instance               RUNNABLE  POSTGRES_15      10.x.x.x
```

### 3. Check API Service Deployment

```bash
kubectl get pods -n $NAMESPACE
kubectl get deployment -n $NAMESPACE
kubectl get svc -n $NAMESPACE
```

Wait for pods to be in **Running** state:

```bash
kubectl wait --for=condition=ready pod -l app=api-service -n $NAMESPACE --timeout=300s
```

### 4. Get Ingress IP

```bash
kubectl get ingress -n $NAMESPACE -w
```

Once an external IP is assigned, test the API:

```bash
INGRESS_IP=$(kubectl get ingress -n $NAMESPACE -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
curl http://$INGRESS_IP/api/records
```

Expected response:
```json
[
  {
    "id": 1,
    "name": "John Doe",
    "position": "Software Engineer",
    ...
  },
  ...
]
```

## Monitoring

### View Pod Logs

```bash
# View API service logs
kubectl logs -n $NAMESPACE deployment/api-service

# View logs from a specific pod
kubectl logs -n $NAMESPACE pod/api-service-xxxxx

# Stream logs in real-time
kubectl logs -n $NAMESPACE deployment/api-service -f
```

### Monitor Horizontal Pod Autoscaler

```bash
# Watch HPA status
kubectl get hpa -n $NAMESPACE -w

# View HPA events
kubectl describe hpa -n $NAMESPACE api-service-hpa
```

### Check Cloud SQL Metrics

```bash
# CPU usage
gcloud sql operations list --instance=$INSTANCE_NAME --project=$PROJECT_ID

# Via Cloud Console
# Navigate to: Cloud SQL > Instances > [instance-name] > Metrics
```

### Port Forward for Local Testing

```bash
kubectl port-forward -n $NAMESPACE service/api-service 5000:5000

# Then test locally
curl http://localhost:5000/api/records
curl http://localhost:5000/health
curl http://localhost:5000/ready
```

### View All Resources

```bash
kubectl get all -n $NAMESPACE
```

## Troubleshooting

### Issue 1: Pods Not Connecting to Cloud SQL

**Symptom**: API pods fail to start, logs show connection timeout

**Solutions**:

1. **Verify VPC configuration**:
   ```bash
   gcloud compute networks describe $VPC_NAME --project=$PROJECT_ID
   ```

2. **Check Cloud SQL has private IP**:
   ```bash
   gcloud sql instances describe $INSTANCE_NAME --project=$PROJECT_ID | grep -A5 ipAddresses
   ```

3. **Verify database exists and user has permissions**:
   ```bash
   gcloud sql databases list --instance=$INSTANCE_NAME --project=$PROJECT_ID
   gcloud sql users list --instance=$INSTANCE_NAME --project=$PROJECT_ID
   ```

4. **Check Kubernetes secret has correct values**:
   ```bash
   kubectl get secret db-credentials -n $NAMESPACE -o yaml
   ```

5. **Test from a pod**:
   ```bash
   kubectl run -it --rm debug --image=postgres:15-alpine --restart=Never -- \
     psql -h $DB_HOST -U $DB_USER -d $DB_NAME
   ```

### Issue 2: Ingress Not Getting External IP

**Symptom**: `EXTERNAL-IP` shows `<pending>`

**Solutions**:

1. **Check ingress status**:
   ```bash
   kubectl describe ingress -n $NAMESPACE
   ```

2. **Wait longer** (GKE ingress can take 5-10 minutes)

3. **Check GCP quotas**:
   ```bash
   gcloud compute project-info describe --project=$PROJECT_ID | grep -A3 QUOTA
   ```

### Issue 3: API Pods Crashing

**Symptom**: Pods restart continuously

**Solutions**:

1. **Check pod logs**:
   ```bash
   kubectl logs -n $NAMESPACE deployment/api-service --previous
   ```

2. **Check readiness probe**:
   ```bash
   kubectl describe pod -n $NAMESPACE -l app=api-service
   ```

3. **Verify database credentials**:
   ```bash
   kubectl exec -it -n $NAMESPACE pod/api-service-xxxxx -- env | grep DB_
   ```

### Issue 4: Database Connection Refused

**Symptom**: Logs show "Connection refused" or "No route to host"

**Solutions**:

1. **Ensure VPC-native cluster**:
   ```bash
   gcloud container clusters describe $CLUSTER --zone=$ZONE | grep -i alias
   ```

2. **Verify network connectivity**:
   ```bash
   kubectl run -it --rm debug --image=ubuntu --restart=Never -- \
     apt-get update && apt-get install -y telnet && telnet $DB_HOST 5432
   ```

3. **Check Cloud SQL flags**:
   ```bash
   gcloud sql instances describe $INSTANCE_NAME --project=$PROJECT_ID | grep flags
   ```

## Security Best Practices

### 1. Use Private IP Only

✅ **Always use Private IP** for production:

```bash
# When creating instance, use --no-assign-ip
--no-assign-ip
```

### 2. Manage Credentials Securely

❌ **Don't**:
- Store passwords in ConfigMaps
- Commit credentials to source control
- Use default passwords

✅ **Do**:
- Use Kubernetes Secrets (encrypted at rest)
- Rotate credentials regularly
- Use strong, unique passwords

Change password:

```bash
gcloud sql users set-password $DB_USER \
  --instance=$INSTANCE_NAME \
  --****** \
  --project=$PROJECT_ID

# Update Kubernetes secret
kubectl set data secret/db-credentials \
  -n $NAMESPACE \
  db-password='NEW_SECURE_PASSWORD'
```

### 3. Enable SSL Connections

For production, enable SSL certificates:

```bash
# Create server certificate
gcloud sql ssl-certs create prod-cert \
  --instance=$INSTANCE_NAME \
  --project=$PROJECT_ID

# Download client certificate if needed
gcloud sql ssl-certs describe prod-cert \
  --instance=$INSTANCE_NAME \
  --project=$PROJECT_ID
```

### 4. Implement IP Whitelisting

Restrict access to Cloud SQL (if using public IP):

```bash
gcloud sql instances patch $INSTANCE_NAME \
  --allowed-networks=IP_RANGE \
  --project=$PROJECT_ID
```

### 5. Enable Audit Logging

```bash
gcloud sql instances patch $INSTANCE_NAME \
  --database-flags=log_connections=on,log_statement=all \
  --project=$PROJECT_ID
```

### 6. Regular Backups

Enable automatic backups:

```bash
gcloud sql instances patch $INSTANCE_NAME \
  --backup-start-time=03:00 \
  --transaction-log-retention-days=7 \
  --project=$PROJECT_ID
```

Create manual backup:

```bash
gcloud sql backups create \
  --instance=$INSTANCE_NAME \
  --project=$PROJECT_ID
```

## Cleanup

### Delete Kubernetes Resources

```bash
# Delete all resources in namespace
kubectl delete namespace $NAMESPACE

# Or delete specific resources
kubectl delete deployment api-service -n $NAMESPACE
kubectl delete service api-service -n $NAMESPACE
kubectl delete hpa api-service-hpa -n $NAMESPACE
kubectl delete ingress api-ingress -n $NAMESPACE
```

### Delete Cloud SQL Instance

```bash
# Note: This deletes the database and all data
gcloud sql instances delete $INSTANCE_NAME \
  --project=$PROJECT_ID
```

### Delete GKE Cluster

```bash
# This terminates all workloads and deletes the cluster
gcloud container clusters delete $CLUSTER \
  --zone $ZONE \
  --project=$PROJECT_ID
```

## Environment-Specific Configurations

### Development Environment

```bash
# Smaller instance for dev
--tier=db-f1-micro
--no-backup  # No automated backups
--point-in-time-recovery-days=0

# Cluster
--num-nodes=1
--machine-type=n1-standard-1
--max-nodes=2
```

### Production Environment

```bash
# Larger instance with HA
--tier=db-n1-standard-2
--availability-type=REGIONAL
--backup-start-time=03:00
--transaction-log-retention-days=7

# Cluster
--num-nodes=3
--machine-type=n1-standard-2
--max-nodes=10
```

## Additional Resources

- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [Cloud SQL Documentation](https://cloud.google.com/sql/docs)
- [Cloud SQL Private IP Setup](https://cloud.google.com/sql/docs/postgres/private-ip)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)
- [GCP Security Best Practices](https://cloud.google.com/security/best-practices)

## Support

For issues or questions:

1. Check the [Troubleshooting](#troubleshooting) section
2. Review the [GKE FAQ](https://cloud.google.com/kubernetes-engine/docs/how-to/faq)
3. Check [Cloud SQL Troubleshooting](https://cloud.google.com/sql/docs/postgres/troubleshooting)
4. Review pod logs: `kubectl logs -n $NAMESPACE deployment/api-service`
