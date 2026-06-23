# Multi-Tier Kubernetes Architecture with Python & PostgreSQL

## Project Overview

This project demonstrates a production-ready multi-tier microservices architecture deployed on Google Kubernetes Engine (GKE) using Python and PostgreSQL.

## Repository Information

- **GitHub Repository**: [sohamsharma-nagarro/kubernetes-multi-tier-architecture](https://github.com/sohamsharma-nagarro/kubernetes-multi-tier-architecture)
- **Docker Hub Images**:
  - API Service: `sohamsharma/py-api-service:latest`

## Architecture Components

### Service API Tier
- **Technology**: Python 3.11 with Flask
- **Port**: 5000
- **Features**:
  - RESTful API endpoints
  - Database connection pooling
  - Health check endpoints (`/health`, `/ready`)
  - ConfigMap-based database configuration
  - Self-healing capabilities
  - Horizontal Pod Autoscaling (HPA)
  - Rolling update support (4 replicas)

### Database Tier
- **Technology**: PostgreSQL 15
- **Port**: 5432
- **Features**:
  - Persistent Volume for data persistence
  - Internal cluster access only
  - Secret-based credentials
  - Auto-recovery after pod deletion
  - 8 pre-loaded employee records

## Quick Start

### Prerequisites
- Google Cloud Account with GKE cluster
- `gcloud` CLI configured
- `kubectl` installed
- Docker installed (for local development)

### Deployment Steps

1. **Clone the repository**
   ```bash
   git clone https://github.com/sohamsharma-nagarro/kubernetes-multi-tier-architecture.git
   cd kubernetes-multi-tier-architecture
   ```

2. **Build and push Docker images to Docker Hub**
   ```bash
   docker build -t sohamsharma/py-api-service:latest ./api
   docker push sohamsharma/py-api-service:latest
   ```

3. **Create GKE cluster (if needed)**
   ```bash
   gcloud container clusters create multi-tier-cluster \
     --zone us-central1-a \
     --num-nodes 3 \
     --machine-type n1-standard-2
   ```

4. **Deploy to Kubernetes**
   ```bash
   chmod +x scripts/deploy.sh
   ./scripts/deploy.sh
   ```

5. **Access the API**
   ```bash
   kubectl get ingress -n multi-tier
   # Use the INGRESS_IP: http://<INGRESS_IP>/api/records
   ```

## API Endpoints

- `GET /api/records` - Retrieve all employee records
- `GET /api/records/<id>` - Retrieve a specific record
- `GET /health` - Liveness probe endpoint
- `GET /ready` - Readiness probe endpoint
- `GET /api/health-info` - Extended health information

## Key Features Demonstrated

✅ **Self-Healing**: Liveness and readiness probes with auto-restart  
✅ **Horizontal Pod Autoscaling**: CPU/Memory-based scaling (2-5 replicas)  
✅ **Rolling Updates**: Zero-downtime deployments  
✅ **Data Persistence**: PostgreSQL with 10Gi PVC  
✅ **Security**: Secrets for credentials, ConfigMaps for configuration  
✅ **FinOps**: Resource optimization and cost monitoring  

## Documentation

- [Requirements Understanding](docs/REQUIREMENTS.md)
- [Assumptions](docs/ASSUMPTIONS.md)
- [Solution Overview](docs/SOLUTION_OVERVIEW.md)
- [Resource Justification](docs/RESOURCE_JUSTIFICATION.md)
- [FinOps Strategy](docs/FINOPS.md)

## Monitoring Commands

```bash
# View all resources
kubectl get all -n multi-tier

# View pod logs
kubectl logs -n multi-tier deployment/api-service
kubectl logs -n multi-tier deployment/postgres-db

# Watch HPA
kubectl get hpa -n multi-tier -w

# Port forward for testing
kubectl port-forward -n multi-tier service/api-service 5000:5000
```

## Testing & Verification

```bash
# Run test script
chmod +x scripts/test-api.sh
./scripts/test-api.sh

# Manual test
curl http://localhost:5000/api/records

# Test self-healing (delete pod)
kubectl delete pod -n multi-tier -l app=api-service
kubectl get pods -n multi-tier

# Test persistence (delete database pod)
kubectl delete pod -n multi-tier -l app=postgres-db
kubectl get pods -n multi-tier
# Data persists via PVC
```

## Cleanup

```bash
chmod +x scripts/cleanup.sh
./scripts/cleanup.sh
```

## Technologies Used

- **Language**: Python 3.11
- **Framework**: Flask
- **Database**: PostgreSQL 15
- **Orchestration**: Kubernetes (GKE)
- **Container Registry**: Docker Hub
- **Infrastructure**: Google Cloud Platform (GCP)

## Author

Soham Sharma (sohamsharma-nagarro)

## License

MIT
