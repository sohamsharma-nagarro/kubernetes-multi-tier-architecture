# Quick Start: Cloud SQL Deployment

A fast reference for deploying to GKE with Cloud SQL.

## One-Liner Setup (If all variables are set)

```bash
./scripts/deploy-cloud-sql.sh
```

## Environment Variables Quick Setup

```bash
cat > /tmp/gke-cloud-sql.env << 'EOF'
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export CLUSTER="api-cluster"
export VPC_NAME="default"
export SUBNET="default"
export INSTANCE_NAME="my-sql-instance"
export DB_NAME="microservices_db"
export DB_USER="dbuser"
export DB_PASS="SecurePassword123!@#"
export NAMESPACE="multi-tier"
export SERVICE_ACCOUNT_NAME="api-k8s-sa"
export IMAGE_TAG="latest"
EOF

source /tmp/gke-cloud-sql.env
```

## Quick Commands Reference

### Enable APIs
```bash
gcloud services enable container.googleapis.com sqladmin.googleapis.com \
  artifactregistry.googleapis.com cloudbuild.googleapis.com iam.googleapis.com
```

### Create GKE Cluster
```bash
gcloud container clusters create $CLUSTER \
  --zone $ZONE --num-nodes=2 --enable-ip-alias \
  --machine-type=n1-standard-2 --project=$PROJECT_ID
```

### Create Cloud SQL
```bash
gcloud sql instances create $INSTANCE_NAME \
  --database-version=POSTGRES_15 --region=$REGION \
  --network=projects/${PROJECT_ID}/global/networks/${VPC_NAME} \
  --no-assign-ip --tier=db-f1-micro
```

### Get Cloud SQL Private IP
```bash
DB_HOST=$(gcloud sql instances describe $INSTANCE_NAME \
  --format="value(ipAddresses[0].ipAddress)")
echo $DB_HOST
```

### Create Kubernetes Secret
```bash
kubectl create secret generic db-credentials \
  -n $NAMESPACE \
  --from-literal=DB_HOST="$DB_HOST" \
  --from-literal=DB_PORT="5432" \
  --from-literal=DB_NAME="$DB_NAME" \
  --from-literal=DB_USER="$DB_USER" \
  --from-literal=DB_PASSWORD="$DB_PASS"
```

### Deploy API
```bash
kubectl apply -f k8s-cloud-sql/
```

### Check Status
```bash
kubectl get pods -n $NAMESPACE
kubectl get ingress -n $NAMESPACE
```

### Get API Endpoint
```bash
kubectl get ingress -n $NAMESPACE -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}'
```

### Test API
```bash
curl http://<INGRESS_IP>/api/records
```

## Troubleshooting Quick Checks

```bash
# Check pods
kubectl get pods -n $NAMESPACE

# Check logs
kubectl logs -n $NAMESPACE deployment/api-service

# Check database connectivity
kubectl run -it --rm debug --image=postgres:15-alpine --restart=Never -- \
  psql -h $DB_HOST -U $DB_USER -d $DB_NAME

# Check Cloud SQL status
gcloud sql instances describe $INSTANCE_NAME --format="value(state)"

# Port forward
kubectl port-forward -n $NAMESPACE service/api-service 5000:5000
curl http://localhost:5000/api/records
```

## Cleanup

```bash
# Delete Kubernetes resources
kubectl delete namespace $NAMESPACE

# Delete Cloud SQL
gcloud sql instances delete $INSTANCE_NAME

# Delete GKE cluster
gcloud container clusters delete $CLUSTER --zone=$ZONE
```

## File Structure

```
.
├── scripts/
│   ├── deploy-cloud-sql.sh          # Automated deployment script
│   ├── deploy.sh                    # Original in-cluster deployment
│   └── test-api.sh
├── k8s-cloud-sql/                   # Cloud SQL specific manifests
│   ├── namespace.yaml
│   ├── configmap.yaml
│   ├── secrets.yaml
│   ├── api-deployment.yaml
│   ├── api-service.yaml
│   ├── api-hpa.yaml
│   └── ingress.yaml
├── k8s/                             # Original in-cluster manifests
├── docs/
│   ├── CLOUD_SQL_DEPLOYMENT.md      # Comprehensive guide
│   └── QUICK_START.md               # This file
└── api/
    └── ...
```

## Key Differences: In-Cluster vs Cloud SQL

| Feature | In-Cluster | Cloud SQL |
|---------|-----------|-----------|
| **Backups** | PVC-based | Managed by Google |
| **HA/Failover** | Manual | Automatic |
| **Scaling** | Cluster-dependent | Independent |
| **Security** | Within cluster | Private VPC IP |
| **Cost** | Cluster resources | Separate charges |
| **Management** | You manage | Google manages |

## Support & Documentation

- Full guide: `docs/CLOUD_SQL_DEPLOYMENT.md`
- GKE docs: https://cloud.google.com/kubernetes-engine/docs
- Cloud SQL docs: https://cloud.google.com/sql/docs
