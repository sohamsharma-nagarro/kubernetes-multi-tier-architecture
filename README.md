# Multi-Tier Kubernetes Architecture with Python & PostgreSQL

## Project Overview

This project demonstrates a production-ready multi-tier microservices architecture deployed on Google Kubernetes Engine (GKE) using Python and PostgreSQL. It features comprehensive Kubernetes best practices including self-healing, horizontal pod autoscaling, rolling updates, persistent data storage, and security implementations.

## Repository Information

- **GitHub Repository**: [sohamsharma-nagarro/kubernetes-multi-tier-architecture](https://github.com/sohamsharma-nagarro/kubernetes-multi-tier-architecture)
- **Docker Hub Images**:
  - API Service: `sohamsharma/py-api-service:latest`

## Architecture Components

### Service API Tier
- **Technology**: Python 3.11 with Flask
- **Port**: 5000
- **Features**:
  - RESTful API endpoints for data retrieval
  - Database connection pooling with error handling
  - Health check endpoints (`/health`, `/ready`)
  - ConfigMap-based database configuration
  - Kubernetes Secrets for secure credential management
  - Self-healing capabilities with liveness/readiness probes
  - Horizontal Pod Autoscaling (HPA) - scales from 2 to 5 replicas
  - Rolling update support with zero-downtime deployments
  - 4 base replicas with automatic pod distribution across nodes

### Database Tier
- **Technology**: PostgreSQL 15 (Alpine-based for minimal footprint)
- **Port**: 5432
- **Features**:
  - Persistent Volume (10Gi) for data persistence
  - Internal cluster access only (ClusterIP service)
  - Secret-based credentials for security
  - Auto-recovery after pod deletion (data persists on PVC)
  - 8 pre-loaded employee records
  - Health probes for availability monitoring

## Quick Start

### 🚀 Deploying in GCP Cloud Shell (Recommended for Quick Setup)

For a complete step-by-step guide to deploy this architecture directly in **Google Cloud Platform using Cloud Shell**, see:

**[📖 GCP Cloud Shell Deployment Guide](docs/GCP_CLOUD_SHELL_DEPLOYMENT.md)**

This comprehensive guide includes:
- ✅ GCP project setup
- ✅ GKE cluster creation from Cloud Shell
- ✅ Docker Hub image configuration
- ✅ Full deployment walkthrough
- ✅ API testing and verification
- ✅ Troubleshooting tips
- ✅ Cost optimization strategies

**Quick command to get started:**
```bash
# 1. Open Cloud Shell at https://console.cloud.google.com
# 2. Set your project ID and clone the repo:
export PROJECT_ID="your-project-id"
gcloud config set project $PROJECT_ID
git clone https://github.com/sohamsharma-nagarro/kubernetes-multi-tier-architecture.git
cd kubernetes-multi-tier-architecture

# 3. Follow the steps in the GCP Cloud Shell Deployment Guide (link above)
```

### Prerequisites
- Google Cloud Account with GKE cluster (or any Kubernetes 1.20+ cluster)
- `gcloud` CLI configured (for GKE)
- `kubectl` installed and configured
- Docker installed (for local development and image building)
- Docker Hub account (for pushing images)

### Deployment Steps

#### 1. Clone the Repository
```bash
git clone https://github.com/sohamsharma-nagarro/kubernetes-multi-tier-architecture.git
cd kubernetes-multi-tier-architecture
```

#### 2. Build and Push Docker Images to Docker Hub
```bash
# Make the script executable
chmod +x scripts/push-docker-hub.sh

# Build and push image (replace 'sohamsharma' with your Docker Hub username)
./scripts/push-docker-hub.sh sohamsharma latest
```

This will:
- Build the Flask API Docker image
- Tag it as `sohamsharma/py-api-service:latest`
- Push it to Docker Hub

#### 3. Create GKE Cluster (if needed)
```bash
gcloud container clusters create multi-tier-cluster \
  --zone us-central1-a \
  --num-nodes 3 \
  --machine-type n1-standard-2 \
  --enable-autoscaling \
  --min-nodes 3 \
  --max-nodes 5
```

#### 4. Deploy to Kubernetes
```bash
# Make deployment script executable
chmod +x scripts/deploy.sh

# Deploy all resources
./scripts/deploy.sh
```

This will:
- Create the `multi-tier` namespace
- Deploy ConfigMaps and Secrets
- Deploy PostgreSQL database with persistent volume
- Deploy Flask API service with 4 replicas
- Configure HPA for automatic scaling
- Set up Ingress for external access

#### 5. Access the API
```bash
# Get the Ingress IP
kubectl get ingress -n multi-tier

# Use the INGRESS_IP to access the API
curl http://<INGRESS_IP>/api/records
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `GET /api/records` | GET | Retrieve all employee records |
| `GET /api/records/<id>` | GET | Retrieve a specific record by ID |
| `GET /health` | GET | Liveness probe endpoint - database connectivity check |
| `GET /ready` | GET | Readiness probe endpoint - initialization verification |
| `GET /api/health-info` | GET | Extended health information with database stats |

### Example API Requests

```bash
# Get all records
curl http://localhost:5000/api/records

# Get specific record
curl http://localhost:5000/api/records/1

# Health check
curl http://localhost:5000/health

# Readiness check
curl http://localhost:5000/ready

# Health info
curl http://localhost:5000/api/health-info
```

## Key Features Demonstrated

✅ **Self-Healing**: Liveness and readiness probes with automatic pod restart  
✅ **Horizontal Pod Autoscaling**: CPU/Memory-based scaling (2-5 replicas)  
✅ **Rolling Updates**: Zero-downtime deployments with configurable update strategy  
✅ **Data Persistence**: PostgreSQL with 10Gi PVC ensuring data survives pod failures  
✅ **Security**: Kubernetes Secrets for credentials, ConfigMaps for configuration  
✅ **FinOps**: Resource optimization with identified cost-saving opportunities  
✅ **High Availability**: Pod anti-affinity and load balancing  
✅ **Connection Pooling**: Efficient database connection management  

## Documentation

Comprehensive documentation is available in the `docs/` directory:

- **[REQUIREMENTS.md](docs/REQUIREMENTS.md)** - Complete requirements specification
  - Service API tier requirements
  - Database tier requirements
  - Kubernetes requirements
  - Testing and deployment requirements

- **[ASSUMPTIONS.md](docs/ASSUMPTIONS.md)** - Design decisions and assumptions
  - Deployment environment assumptions
  - Architectural assumptions
  - Technology choices rationale
  - Limitations and future considerations

- **[GCP_CLOUD_SHELL_DEPLOYMENT.md](docs/GCP_CLOUD_SHELL_DEPLOYMENT.md)** - Step-by-step GCP Cloud Shell deployment guide
  - GCP project setup and GKE cluster creation
  - Docker Hub image configuration
  - Complete deployment walkthrough
  - API testing and verification
  - Troubleshooting tips and best practices
  - Cost optimization for GCP

- **[SOLUTION_OVERVIEW.md](docs/SOLUTION_OVERVIEW.md)** - Architecture and implementation details
  - System architecture diagram
  - Component interaction flows
  - Kubernetes resources explanation
  - Self-healing and HA mechanisms
  - Performance characteristics

- **[RESOURCE_JUSTIFICATION.md](docs/RESOURCE_JUSTIFICATION.md)** - CPU/Memory resource justification
  - API service resource allocation rationale
  - Database resource allocation rationale
  - HPA scaling analysis
  - Cost optimization opportunities

- **[FINOPS.md](docs/FINOPS.md)** - Cost optimization strategies
  - Current cost model analysis
  - **3 Cost Optimization Opportunities**:
    1. Compute right-sizing and reserved instances (79% savings)
    2. Storage optimization (80-90% savings)
    3. Node consolidation with preemptible nodes (58% savings)
  - Combined potential savings: **81% monthly cost reduction**
  - Cost monitoring strategy
  - Implementation roadmap

## Monitoring and Operations

### View Deployment Status
```bash
# View all resources in the namespace
kubectl get all -n multi-tier

# View pods
kubectl get pods -n multi-tier -w

# View services
kubectl get svc -n multi-tier

# View HPA status
kubectl get hpa -n multi-tier -w
```

### View Logs
```bash
# View API service logs
kubectl logs -n multi-tier deployment/api-service

# View database logs
kubectl logs -n multi-tier deployment/postgres-db

# View specific pod logs
kubectl logs -n multi-tier <pod-name>

# Stream logs in real-time
kubectl logs -f -n multi-tier deployment/api-service
```

### Port Forwarding for Local Testing
```bash
# Forward API service to local port 5000
kubectl port-forward -n multi-tier service/api-service 5000:80

# Forward database to local port 5432
kubectl port-forward -n multi-tier service/postgres-db 5432:5432
```

### Verify Deployment
```bash
# Make verification script executable
chmod +x scripts/verify.sh

# Run comprehensive verification
./scripts/verify.sh
```

This will verify:
- Kubernetes cluster access
- All Kubernetes resources are deployed
- ConfigMaps and Secrets are configured
- All pods are healthy and running
- Services are properly exposed
- Database has data persistence configured
- API endpoints are responding
- Resource requests and limits are set

## Testing

### Unit Tests
```bash
# Install test dependencies
pip install -r api/requirements.txt

# Run API tests
cd api
python -m pytest tests/ -v

# Run with coverage
python -m pytest tests/ -v --cov=.
```

### API Integration Tests
```bash
# Make test script executable
chmod +x scripts/test-api.sh

# Run API tests (requires deployed cluster)
./scripts/test-api.sh
```

## Local Development with Docker Compose

For local development without Kubernetes:

```bash
# Start local environment
docker-compose up -d

# Access API
curl http://localhost:5000/api/records

# View logs
docker-compose logs -f api-service

# Stop services
docker-compose down

# Clean up volumes
docker-compose down -v
```

## Self-Healing and Resilience Testing

### Test Pod Auto-Restart
```bash
# Get pod name
POD_NAME=$(kubectl get pods -n multi-tier -l app=api-service -o jsonpath='{.items[0].metadata.name}')

# Delete pod (will automatically restart)
kubectl delete pod -n multi-tier $POD_NAME

# Watch pod restart
kubectl get pods -n multi-tier -l app=api-service -w
```

### Test Data Persistence
```bash
# Get database pod name
DB_POD=$(kubectl get pods -n multi-tier -l app=postgres-db -o jsonpath='{.items[0].metadata.name}')

# Delete database pod (data persists on PVC)
kubectl delete pod -n multi-tier $DB_POD

# Watch pod restart with data intact
kubectl get pods -n multi-tier -l app=postgres-db -w

# Verify data still exists
curl http://<ingress-ip>/api/records
```

### Test Horizontal Pod Autoscaling
```bash
# Watch HPA status
kubectl get hpa -n multi-tier -w

# Generate load (in another terminal)
kubectl run -i --tty load-generator -n multi-tier --rm --image=busybox --restart=Never -- /bin/sh

# In the load generator pod
while sleep 0.01; do wget -q -O- http://api-service/api/records; done

# Watch pods scale up in another terminal
kubectl get pods -n multi-tier -l app=api-service -w
```

## Rolling Updates

### Deploy a New Version
```bash
# Update the image tag in k8s/api-deployment.yaml
# Then apply the deployment

kubectl apply -f k8s/api-deployment.yaml -n multi-tier

# Watch the rolling update
kubectl get pods -n multi-tier -l app=api-service -w
kubectl rollout status deployment/api-service -n multi-tier
```

## Cleanup

### Remove All Deployments
```bash
# Make cleanup script executable
chmod +x scripts/cleanup.sh

# Remove all resources from the cluster
./scripts/cleanup.sh
```

Or manually:
```bash
# Delete namespace (removes all resources)
kubectl delete namespace multi-tier
```

## Technologies Used

- **Language**: Python 3.11
- **Framework**: Flask 3.0.0
- **Database**: PostgreSQL 15
- **Database Driver**: psycopg2-binary
- **Server**: Gunicorn 21.2.0
- **Orchestration**: Kubernetes (GKE/Any K8s 1.20+)
- **Container Runtime**: Docker
- **Container Registry**: Docker Hub

## Project Structure

```
kubernetes-multi-tier-architecture/
├── api/                           # Flask API service
│   ├── app.py                    # Flask application
│   ├── Dockerfile                # Multi-stage Dockerfile
│   ├── requirements.txt           # Python dependencies
│   └── tests/                    # Unit tests
│       ├── __init__.py
│       └── test_app.py           # API endpoint tests
├── database/                      # Database configuration
│   ├── Dockerfile                # PostgreSQL Dockerfile
│   └── init.sql                  # Database initialization script
├── k8s/                          # Kubernetes manifests
│   ├── namespace.yaml            # Namespace definition
│   ├── configmap.yaml            # Database configuration
│   ├── secrets.yaml              # Database credentials
│   ├── db-pvc.yaml               # Persistent volume claim
│   ├── db-deployment.yaml        # PostgreSQL deployment
│   ├── db-service.yaml           # Database service
│   ├── db-init-configmap.yaml    # Database initialization script
│   ├── api-deployment.yaml       # Flask API deployment
│   ├── api-service.yaml          # API service
│   ├── api-hpa.yaml              # Horizontal pod autoscaler
│   └── ingress.yaml              # Ingress configuration
├── scripts/                       # Automation scripts
│   ├── deploy.sh                 # Deployment script
│   ├── test-api.sh               # API testing script
│   ├── verify.sh                 # Verification script
│   ├── cleanup.sh                # Cleanup script
│   └── push-docker-hub.sh        # Docker Hub push script
├── docs/                         # Documentation
│   ├── REQUIREMENTS.md           # Requirements specification
│   ├── ASSUMPTIONS.md            # Design decisions
│   ├── SOLUTION_OVERVIEW.md      # Architecture details
│   ├── RESOURCE_JUSTIFICATION.md # Resource allocation
│   └── FINOPS.md                 # Cost optimization
├── docker-compose.yaml            # Local development setup
├── README.md                       # This file
└── LICENSE                        # MIT License
```

## Cost Optimization

This project includes a comprehensive FinOps strategy document. Key optimization opportunities identified:

1. **Compute Right-Sizing**: 79% savings through CPU/memory optimization and reserved instances
2. **Storage Optimization**: 80-90% savings through volume downsizing and snapshot lifecycle policies
3. **Node Consolidation**: 58% savings through preemptible nodes and better bin-packing

**Combined Potential Savings**: 81% monthly cost reduction ($20,580/year on estimated $25,440 baseline)

See [FINOPS.md](docs/FINOPS.md) for detailed analysis and implementation strategies.

## Troubleshooting

### API Pod Not Starting
```bash
# Check pod status and events
kubectl describe pod -n multi-tier <api-pod-name>

# Check logs for errors
kubectl logs -n multi-tier <api-pod-name>

# Common issues:
# 1. Database not ready - API probe will fail
# 2. ConfigMap/Secret not found - Pod will fail to start
# 3. Image pull errors - Check image exists in Docker Hub
```

### Database Pod Not Starting
```bash
# Check database pod status
kubectl describe pod -n multi-tier <db-pod-name>

# Check database logs
kubectl logs -n multi-tier <db-pod-name>

# Common issues:
# 1. PVC not bound - Check storage availability
# 2. Init script error - Check ConfigMap content
# 3. Port conflicts - Ensure port 5432 is available
```

### API Returns 503 Service Unavailable
- Database pod may not be ready
- Connection pool may have failed
- Check database pod status: `kubectl get pods -n multi-tier -l app=postgres-db`
- Check database logs: `kubectl logs -n multi-tier <db-pod-name>`

### Data Not Persisting
- Verify PVC exists: `kubectl get pvc -n multi-tier`
- Check PVC status: `kubectl get pvc postgres-pvc -n multi-tier -o yaml`
- Ensure storage class is available: `kubectl get storageclass`

## Performance Tuning

### Increase Connection Pool Size
Edit `k8s/api-deployment.yaml` and update the connection pool size in `app.py`

### Adjust HPA Thresholds
Edit `k8s/api-hpa.yaml` to change:
- CPU threshold (default: 50%)
- Memory threshold (default: 70%)
- Min/max replicas (default: 2-5)

### Increase Resource Limits
Edit resource requests/limits in deployment YAML files based on your workload

## Contributing

Contributions are welcome! Please ensure:
1. Code follows Python PEP 8 style guide
2. All tests pass
3. Documentation is updated
4. Kubernetes manifests are valid

## Support

For issues, questions, or contributions, please open an issue on GitHub.

## Author

Soham Sharma (sohamsharma-nagarro)

## License

MIT
