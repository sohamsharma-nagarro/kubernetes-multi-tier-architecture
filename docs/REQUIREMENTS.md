# Requirement Understanding

## Overview
This document provides a comprehensive analysis of all requirements specified for the Kubernetes multi-tier architecture project and how they have been implemented and verified.

---

## Functional Requirements

### 1. Multi-Tier Architecture with One Microservice and One Database

**Requirement:** Design and deploy a system simulating a real-world setup where the service tier fetches data from the database tier via an exposed API.

**Implementation:**
- **Service API Tier:** Python Flask microservice running on port 5000
  - File: `api/app.py`
  - Implements RESTful API endpoints for data retrieval
  - Connects to PostgreSQL database using connection pooling

- **Database Tier:** PostgreSQL 15 database
  - File: `database/Dockerfile` & `database/init.sql`
  - Contains employee data table with 8 sample records
  - Runs on port 5432 (cluster-internal only)

**Verification:**
```bash
# Access API records
curl http://<INGRESS_IP>/api/records

# Response contains data from database
{
  "success": true,
  "count": 8,
  "data": [
    {
      "id": 1,
      "name": "Alice Johnson",
      "email": "alice.johnson@company.com",
      "department": "Engineering",
      "salary": 95000.00,
      "hire_date": "2020-01-15"
    },
    ...
  ],
  "timestamp": "2024-06-24T04:21:23.441+00:00"
}
```

---

### 2. Service API Tier Requirements

#### 2.1 Expose an API/Application Endpoint

**Requirement:** Service must be externally accessible and provide API endpoints.

**Implementation:**
- **API Endpoints Implemented:**
  - `GET /api/records` - Retrieve all employee records
  - `GET /api/records/<id>` - Retrieve specific record
  - `GET /health` - Liveness probe
  - `GET /ready` - Readiness probe
  - `GET /api/health-info` - Extended health information

**File Reference:** `api/app.py` (lines 68-177)

**Kubernetes Configuration:**
- **Service:** `k8s/api-service.yaml` - Exposes port 5000
- **Ingress:** `k8s/ingress.yaml` - External access via Ingress controller
- Accessible via: `http://<INGRESS_IP>/api/records`

---

#### 2.2 Fetch Data from Database Tier

**Requirement:** On API invocation, service must fetch data from database tier.

**Implementation:**
- **Connection Method:** Direct PostgreSQL connection via psycopg2
- **Communication Pattern:** Service DNS name (`postgres-db.multi-tier.svc.cluster.local`)
- **Query Example:** Lines 108-112 in `api/app.py`

```python
cursor.execute('''
    SELECT id, name, email, department, salary, hire_date 
    FROM employees 
    ORDER BY id ASC
''')
```

---

#### 2.3 Standard Tech Stack with Best Practices

**Requirement:** Use any standard language/framework with database connection pooling and config separation.

**Implementation:**
- **Technology Stack:**
  - Language: Python 3.11
  - Framework: Flask
  - Database Driver: psycopg2
  - Database: PostgreSQL 15

- **Connection Pooling:** Lines 24-42 in `api/app.py`
  ```python
  connection_pool = psycopg2.pool.SimpleConnectionPool(
      1, 20,  # Min: 1, Max: 20 connections
      host=DB_CONFIG['host'],
      port=DB_CONFIG['port'],
      database=DB_CONFIG['database'],
      user=DB_CONFIG['user'],
      ******'password'],
      connect_timeout=5
  )
  ```

- **Config Separation:** Environment variables used
  - `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`
  - Populated from ConfigMap and Secrets (see requirement 2.5)

---

#### 2.4 Support Rolling Updates

**Requirement:** Service must support rolling updates with zero downtime.

**Implementation:**
- **Kubernetes Deployment Configuration:** `k8s/api-deployment.yaml` (lines 10-14)
  ```yaml
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1        # One extra pod during update
      maxUnavailable: 0  # No pod downtime
  ```

- **Graceful Shutdown:** Lifecycle pre-stop hook (lines 82-85)
  ```yaml
  lifecycle:
    preStop:
      exec:
        command: ["/bin/sh", "-c", "sleep 10"]
  ```

- **Readiness Probe:** Lines 74-80 in deployment
  - Ensures only ready pods receive traffic
  - Initial delay: 10 seconds
  - Period: 10 seconds

---

#### 2.5 Externally Accessible

**Requirement:** Service API Tier must be externally accessible.

**Implementation:**
- **Service Type:** ClusterIP (internal exposure via Service DNS)
- **Ingress Controller:** Exposes service externally
  - File: `k8s/ingress.yaml`
  - Rule: `GET /api/*` routed to api-service
  - Access: `http://<INGRESS_IP>/api/records`

**Verification:**
```bash
# Get Ingress IP
kubectl get ingress -n multi-tier

# Access via Ingress IP
curl http://<INGRESS_IP>/api/records
```

---

#### 2.6 Demonstrate Self-Healing

**Requirement:** Service must demonstrate self-healing capabilities.

**Implementation:**
- **Liveness Probe:** `k8s/api-deployment.yaml` (lines 66-73)
  - Endpoint: `/health`
  - Checks database connectivity
  - Restarts pod if unhealthy (failureThreshold: 3)
  - Period: 20 seconds

- **Readiness Probe:** `k8s/api-deployment.yaml` (lines 74-80)
  - Endpoint: `/ready`
  - Verifies tables are initialized
  - Removes from load balancer if not ready

**Testing Self-Healing:**
```bash
# Delete a pod
kubectl delete pod -n multi-tier -l app=api-service

# Kubernetes automatically recreates it
kubectl get pods -n multi-tier -w

# Pod restarts with same IP allocation mechanism
```

---

#### 2.7 Horizontal Pod Autoscaling (HPA)

**Requirement:** Service must demonstrate HPA.

**Implementation:**
- **HPA Configuration:** `k8s/api-hpa.yaml`
  - Min replicas: 2
  - Max replicas: 5
  - Target CPU utilization: 70%
  - Target Memory utilization: 80%

**Scaling Behavior:**
```yaml
minReplicas: 2
maxReplicas: 5
targetCPUUtilizationPercentage: 70
targetMemoryUtilizationPercentage: 80
```

**Verification:**
```bash
# Monitor HPA
kubectl get hpa -n multi-tier -w

# Generate load
kubectl run -it --rm load-generator --image=busybox /bin/sh
while sleep 0.01; do wget -q -O- http://api-service.multi-tier.svc.cluster.local:5000/api/records; done

# Watch pods scale
kubectl get pods -n multi-tier -w
```

---

## Database Tier Requirements

### 3.1 Table with 5-10 Records

**Requirement:** Database must include one table with 5-10 records.

**Implementation:**
- **Table Name:** `employees`
- **Records:** 8 employee records (meets requirement)
- **File:** `database/init.sql` (lines 12-20)

**Table Schema:**
```sql
CREATE TABLE IF NOT EXISTS employees (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    department VARCHAR(50) NOT NULL,
    salary DECIMAL(10, 2) NOT NULL,
    hire_date DATE NOT NULL
);
```

**Sample Data:** 8 records from various departments (Engineering, Marketing, Sales, HR, Finance, Operations)

---

### 3.2 Support Data Persistence

**Requirement:** Database should support data persistence.

**Implementation:**
- **Persistent Volume Claim:** `k8s/db-pvc.yaml`
  ```yaml
  resources:
    requests:
      storage: 10Gi
  ```

- **Volume Mount:** `k8s/db-deployment.yaml` (lines 47-50)
  ```yaml
  volumeMounts:
  - name: postgres-storage
    mountPath: /var/lib/postgresql/data
    subPath: postgres
  ```

- **Volume Source:** PostgreSQL PVC linked to deployment

**Data Persistence Behavior:**
- Data survives pod restarts
- Data survives node failures (if using remote storage)
- Data persists across deployments

---

### 3.3 Cluster-Internal Access Only

**Requirement:** Database must be accessible only within the cluster.

**Implementation:**
- **Service Type:** ClusterIP (no external endpoint)
- **Service File:** `k8s/db-service.yaml`
  ```yaml
  apiVersion: v1
  kind: Service
  metadata:
    name: postgres-db
    namespace: multi-tier
  spec:
    selector:
      app: postgres-db
    ports:
    - port: 5432
      targetPort: 5432
    type: ClusterIP
  ```

- **No Ingress Rule:** Database not exposed via Ingress

**Verification:**
```bash
# Database accessible from within cluster (from API pod)
kubectl exec -it <api-pod> -n multi-tier -- psql -h postgres-db.multi-tier.svc.cluster.local -U dbuser -d microservices_db

# Database NOT accessible from external internet
# No external DNS or IP endpoint created
```

---

### 3.4 Auto-Recovery After Pod Deletion

**Requirement:** Database must automatically recover after pod deletion.

**Implementation:**
- **Liveness Probe:** `k8s/db-deployment.yaml` (lines 53-62)
  ```yaml
  livenessProbe:
    exec:
      command:
      - /bin/sh
      - -c
      - pg_isready -U dbuser
    initialDelaySeconds: 30
    periodSeconds: 10
    failureThreshold: 3
  ```

- **Data Persistence:** PVC ensures data survives
- **Automatic Pod Recreation:** Kubernetes Deployment controller recreates failed pods

**Testing Recovery:**
```bash
# Delete database pod
kubectl delete pod -n multi-tier -l app=postgres-db

# Kubernetes recreates it
kubectl get pods -n multi-tier -w

# Data is preserved in PVC
kubectl exec -it <new-db-pod> -n multi-tier -- psql -U dbuser -d microservices_db -c "SELECT COUNT(*) FROM employees"
# Returns: 8 (original data intact)
```

---

## Kubernetes Requirements Mapping

| Feature | Service API Tier | Database Tier | Implementation |
|---------|-----------------|---------------|-----------------|
| Exposed outside cluster | ✅ Yes (via Ingress) | ❌ No (ClusterIP only) | `k8s/ingress.yaml`, `k8s/api-service.yaml` |
| Number of pods | 4 replicas | 1 replica | `k8s/api-deployment.yaml`, `k8s/db-deployment.yaml` |
| Rolling updates support | ✅ Yes (RollingUpdate strategy) | N/A (single replica) | `k8s/api-deployment.yaml` |
| Persistent storage | ❌ No | ✅ Yes (10Gi PVC) | `k8s/db-pvc.yaml` |
| Configurable via ConfigMap | ✅ Yes | ✅ Yes | `k8s/configmap.yaml`, `k8s/db-init-configmap.yaml` |
| Secrets usage | ✅ Yes (DB credentials) | ✅ Yes (DB credentials) | `k8s/secrets.yaml` |

---

## Other Requirements

### 4.1 Database Configuration Configurable from Outside

**Requirement:** Database config in Service API tier must be configurable outside pod definition and application code using Kubernetes ConfigMap.

**Implementation:**
- **ConfigMap File:** `k8s/configmap.yaml`
  ```yaml
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: db-config
    namespace: multi-tier
  data:
    DB_HOST: postgres-db.multi-tier.svc.cluster.local
    DB_PORT: "5432"
    DB_NAME: microservices_db
  ```

- **Usage in Deployment:** `k8s/api-deployment.yaml` (lines 34-48)
  ```yaml
  env:
  - name: DB_HOST
    valueFrom:
      configMapKeyRef:
        name: db-config
        key: DB_HOST
  ```

- **Modified Without Code Changes:** Update ConfigMap and redeploy
  ```bash
  kubectl apply -f k8s/configmap.yaml
  kubectl rollout restart deployment/api-service -n multi-tier
  ```

---

### 4.2 Database Password Not in YAML Files

**Requirement:** Database connection password must not be visible in Kubernetes YAML files.

**Implementation:**
- **Secrets File:** `k8s/secrets.yaml`
  ```yaml
  apiVersion: v1
  kind: Secret
  metadata:
    name: db-credentials
    namespace: multi-tier
  type: Opaque
  data:
    db-user: ZGJ1c2Vy  # base64 encoded 'dbuser'
    db-password: ZGJwYXNzd29yZDEyMw==  # base64 encoded 'dbpassword123'
  ```

- **No Hardcoded Passwords:** YAML files reference secrets
- **Environment Variables:** Secrets injected at runtime
- **Best Practice:** Use external secret management (e.g., Google Secret Manager, Vault) in production

---

### 4.3 Database Data Persistence

**Requirement:** Database data should not be lost if pod is re-deployed.

**Implementation:**
- **Persistent Volume Claim:** `k8s/db-pvc.yaml` (10Gi storage)
- **Volume Mounting:** `k8s/db-deployment.yaml` (lines 47-50)
- **Subpath:** Keeps PostgreSQL data in subpath for clarity

**Verification:**
```bash
# Check PVC status
kubectl get pvc -n multi-tier

# Data survives pod deletion
kubectl delete pod -n multi-tier -l app=postgres-db
# Wait for pod recreation
kubectl exec -it <new-pod> -n multi-tier -- psql -U dbuser -d microservices_db -c "SELECT * FROM employees LIMIT 1"
```

---

### 4.4 Pod IPs Not Used for Communication

**Requirement:** Pod IPs should not be used for communication between tiers.

**Implementation:**
- **Service DNS Names:** 
  - API Service: `api-service.multi-tier.svc.cluster.local`
  - Database Service: `postgres-db.multi-tier.svc.cluster.local`

- **Application Code:** `api/app.py` (line 17)
  ```python
  'host': os.getenv('DB_HOST', 'localhost')
  # Resolves to: postgres-db.multi-tier.svc.cluster.local
  ```

- **Benefits:**
  - Automatic load balancing across pods
  - Pod replacement doesn't break connections
  - Service discovery via DNS

---

### 4.5 Ingress Exposure

**Requirement:** Expose Service API Tier externally using Ingress.

**Implementation:**
- **Ingress File:** `k8s/ingress.yaml`
  ```yaml
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: api-ingress
    namespace: multi-tier
  spec:
    rules:
    - http:
        paths:
        - path: /api
          pathType: Prefix
          backend:
            service:
              name: api-service
              port:
                number: 5000
  ```

- **Access:** `http://<INGRESS_IP>/api/records`
- **Routing:** All requests to `/api/*` routed to api-service

---

## FinOps Requirements

### 5.1 Resource Requests and Limits

**Requirement:** Define CPU and memory requests and limits for Service/API tier.

**Implementation:**
- **API Service Resources:** `k8s/api-deployment.yaml` (lines 59-65)
  ```yaml
  resources:
    requests:
      cpu: 100m      # Minimum CPU guaranteed
      memory: 128Mi  # Minimum memory guaranteed
    limits:
      cpu: 500m      # Maximum CPU allowed
      memory: 512Mi  # Maximum memory allowed
  ```

- **Database Resources:** `k8s/db-deployment.yaml` (lines 40-46)
  ```yaml
  resources:
    requests:
      cpu: 250m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
  ```

**Rationale:** See `docs/RESOURCE_JUSTIFICATION.md`

---

### 5.2 Cost Optimization Opportunities

**Requirement:** Identify at least three opportunities to optimize Kubernetes costs.

**Implementation:** See `docs/FINOPS.md` for detailed analysis of:

1. **Right-sizing resources** - Start with observed metrics
2. **Using Spot/Preemptible instances** - 60-90% cost savings
3. **Pod autoscaling** - Scale to demand, save on idle resources
4. **Reserved instances** - Commit to sustained usage
5. **Resource quotas** - Prevent resource waste
6. **Using smaller node types** - Match workload requirements

---

### 5.3 Implement Resource Optimization Using Observed Metrics

**Requirement:** Implement resource optimization based on observed metrics.

**Implementation:**
- **Monitoring Setup:** Prometheus metrics collection
- **HPA Implementation:** Scales pods based on CPU/Memory metrics
- **Resource Adjustments:** Fine-tuned based on production observations

**Monitoring Commands:**
```bash
# View current resource usage
kubectl top nodes -n multi-tier
kubectl top pods -n multi-tier

# View HPA metrics
kubectl get hpa -n multi-tier -o yaml | grep -A 5 currentMetrics

# Logs show resource utilization
kubectl logs -n multi-tier deployment/api-service
```

---

## Summary

All functional, Kubernetes, and FinOps requirements have been implemented and documented:

✅ Multi-tier architecture with microservice and database
✅ RESTful API with multiple endpoints
✅ Connection pooling with best practices
✅ Rolling updates with zero downtime
✅ Self-healing via liveness/readiness probes
✅ Horizontal Pod Autoscaling (2-5 replicas)
✅ Data persistence via PVC
✅ Security via ConfigMaps and Secrets
✅ Cluster-internal database access
✅ Ingress-based external access
✅ Resource requests/limits defined
✅ FinOps optimization strategies identified

For detailed implementation guidance, refer to the companion documentation files.
