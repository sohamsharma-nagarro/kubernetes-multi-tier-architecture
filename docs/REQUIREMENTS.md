# Requirements Specification

## Overview
This document details the requirements for a multi-tier Kubernetes architecture consisting of a service API tier and a database tier.

## Service API Tier Requirements

### Functional Requirements
- **REST API Interface**: Expose HTTP endpoints for data retrieval
- **Data Source**: Fetch data from the database tier via API calls
- **Record Retrieval**: Support endpoints to retrieve all records and individual records by ID
- **Health Monitoring**: Implement health check and readiness probe endpoints
- **Extended Information**: Provide endpoint for extended health and database information

### Technical Requirements
- **Language/Framework**: Python 3.11 with Flask framework
- **Port**: 5000 (HTTP)
- **Dependencies**: Flask, psycopg2-binary, gunicorn, requests

### Database Connectivity
- **Connection Method**: PostgreSQL client library with connection pooling
- **Connection Pooling**: Implement SimpleConnectionPool (min: 1, max: 20 connections)
- **Configuration**: Database connection parameters via environment variables
- **Credential Security**: Database password stored securely using Kubernetes Secrets
- **Configuration Management**: Database host, port, and name via ConfigMaps
- **Connection Timeout**: 5 seconds with proper error handling

### API Endpoints
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Liveness probe - database connectivity check |
| `/ready` | GET | Readiness probe - table existence verification |
| `/api/records` | GET | Retrieve all employee records |
| `/api/records/<id>` | GET | Retrieve specific employee record by ID |
| `/api/health-info` | GET | Extended health information with database version |

### Non-Functional Requirements
- **Availability**: 4 replicas minimum
- **Scalability**: Horizontal Pod Autoscaling (HPA) enabled
  - Minimum replicas: 2
  - Maximum replicas: 5
  - CPU threshold: 50% utilization
  - Memory threshold: 70% utilization
- **Updates**: Support rolling updates with zero downtime
  - Max surge: 1 pod
  - Max unavailable: 0 pods
  - Pre-stop hook: 10-second grace period
- **Self-Healing**: Liveness and readiness probes with automatic restart
- **Resource Constraints**:
  - CPU request: 100m
  - CPU limit: 500m
  - Memory request: 128Mi
  - Memory limit: 512Mi
- **Pod Distribution**: Pod anti-affinity to prefer distribution across different nodes

## Database Tier Requirements

### Functional Requirements
- **Database System**: PostgreSQL 15
- **Port**: 5432
- **Data**: Pre-loaded with 5-10 employee records
- **Schema**: Single table (employees) with structured data
- **Accessibility**: Internal cluster access only (not exposed externally)

### Technical Requirements
- **Image**: PostgreSQL 15-alpine official image
- **Replicas**: 1 (stateful)
- **Resource Constraints**:
  - CPU request: 250m
  - CPU limit: 500m
  - Memory request: 256Mi
  - Memory limit: 512Mi

### Data Persistence
- **Storage Type**: PersistentVolumeClaim (PVC)
- **Storage Size**: 10Gi
- **Access Mode**: ReadWriteOnce
- **Persistence**: Data survives pod deletion and restart
- **Volume Mount**: `/var/lib/postgresql/data` with subPath: postgres

### Security
- **Credentials**: Database user and password via Kubernetes Secrets
- **Internal Access**: ClusterIP service (no external access)
- **Connection Security**: Credentials never exposed in configuration files

### Data Initialization
- **Initialization Method**: SQL script via ConfigMap
- **Mounted Path**: `/docker-entrypoint-initdb.d`
- **Tables**: employees table with 8 pre-loaded records
- **Schema**:
  - id: SERIAL PRIMARY KEY
  - name: VARCHAR(100)
  - email: VARCHAR(100) UNIQUE
  - department: VARCHAR(50)
  - salary: DECIMAL(10, 2)
  - hire_date: DATE

### High Availability
- **Liveness Probe**: pg_isready command
  - Initial delay: 30 seconds
  - Period: 10 seconds
  - Timeout: 5 seconds
  - Failure threshold: 3
- **Readiness Probe**: pg_isready command
  - Initial delay: 5 seconds
  - Period: 10 seconds
  - Timeout: 3 seconds
  - Failure threshold: 3

## Kubernetes Requirements

### Namespace
- **Name**: multi-tier
- **Isolation**: All resources deployed in this namespace

### ConfigMaps
- **db-config**: Database connection parameters (host, port, name)
- **init-script**: SQL initialization script for database

### Secrets
- **db-credentials**: Database credentials (user, password)
- **Type**: Opaque
- **Encoding**: Kubernetes automatic base64 encoding

### Services
- **api-service**: LoadBalancer service for external access
  - Port: 80 (external)
  - Target Port: 5000 (container)
- **postgres-db**: ClusterIP service for internal access
  - Port: 5432 (internal)
  - Target Port: 5432 (container)

### Ingress
- **Name**: api-ingress
- **Type**: Ingress (GCE)
- **Path**: `/` (all traffic)
- **Backend**: api-service on port 80

### Horizontal Pod Autoscaler (HPA)
- **Target**: api-service Deployment
- **Metrics**:
  - CPU utilization: 50% threshold
  - Memory utilization: 70% threshold
- **Scaling Behavior**:
  - Scale-up: 100% increase every 30 seconds (max 2 pods per 60 seconds)
  - Scale-down: 50% decrease every 60 seconds
  - Stabilization window: 30 seconds for scale-up, 300 seconds for scale-down

### Persistent Volumes
- **postgres-pvc**: PersistentVolumeClaim
  - Size: 10Gi
  - Access Mode: ReadWriteOnce
  - Storage Class: standard

## FinOps Requirements

### Resource Definition
All pods must have defined CPU and memory requests and limits for proper cost tracking and optimization.

### Cost Optimization
Identify and implement at least 3 cost optimization opportunities:
1. **Pod Density Optimization**: Right-size resource requests based on actual usage patterns
2. **Reserved Capacity**: Use a mix of on-demand and reserved instances
3. **Storage Optimization**: Use appropriate storage classes and implement lifecycle policies

### Monitoring
- Track actual resource utilization
- Implement automated scaling based on observed metrics
- Generate reports on resource efficiency

## Container Registry

### Docker Hub
- **API Service Image**: `sohamsharma/py-api-service:latest`
- **Database Image**: Official PostgreSQL 15-alpine image
- **Build Process**: Multi-stage Dockerfile for optimized image size

## Testing Requirements

### Unit Tests
- API endpoint functionality tests
- Database connection tests
- Error handling verification

### Integration Tests
- End-to-end API to database communication
- Health check verification
- Data persistence verification

### Deployment Tests
- Self-healing capability (pod deletion and recovery)
- Rolling update verification
- Scaling behavior validation

## Documentation Requirements

- **Architecture Overview**: Solution design and component interaction
- **Deployment Instructions**: Step-by-step deployment guide
- **API Documentation**: Endpoint descriptions and usage examples
- **Troubleshooting Guide**: Common issues and resolutions
- **Monitoring Guide**: How to monitor application health and performance

## Constraints

- All communication between tiers must use service names, not pod IPs
- Database configuration must be externally configurable
- Database credentials must not appear in pod definition files
- Application must support Kubernetes best practices
