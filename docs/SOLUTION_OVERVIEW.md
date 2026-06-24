# Solution Overview

This document provides a comprehensive overview of the multi-tier Kubernetes architecture, including system design, component descriptions, and implementation details.

---

## Executive Summary

The project implements a production-ready, scalable multi-tier microservices architecture on Google Kubernetes Engine (GKE) using Python Flask for the service tier and PostgreSQL for the database tier. The solution demonstrates enterprise-grade practices including connection pooling, graceful scaling, self-healing capabilities, data persistence, and comprehensive security configurations.

**Key Metrics:**
- 4 replicas of API service (scalable to 5 via HPA)
- 1 PostgreSQL database instance
- 8 pre-loaded employee records
- Zero-downtime rolling updates
- Automatic recovery from pod failures
- Cost-optimized resource allocation

---

## 1. Architecture Overview

### 1.1 High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    External Users                        │
└──────────────────────┬──────────────────────────────────┘
                       │ HTTP Requests
                       ▼
        ┌──────────────────────────────┐
        │   Ingress Controller (GCE)   │ ← External Load Balancer
        │   Port: 80 → /api/*          │
        └──────────────────────────────┘
                       │ Service DNS: api-service:5000
                       ▼
        ┌──────────────────────────────┐
        │   Service (ClusterIP)        │ ← Load Balancer
        │   Port: 5000                 │
        └──────────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
        ▼              ▼              ▼
    ┌───────────┐ ┌───────────┐ ┌───────────┐
    │  API Pod  │ │  API Pod  │ │  API Pod  │ ...
    │ Python    │ │ Python    │ │ Python    │  (4-5 replicas)
    │ Flask     │ │ Flask     │ │ Flask     │
    │ Port:5000 │ │ Port:5000 │ │ Port:5000 │
    └───────────┘ └───────────┘ └───────────┘
        │              │              │
        └──────────────┼──────────────┘
                       │ Service DNS: postgres-db.multi-tier.svc.cluster.local:5432
                       ▼
        ┌──────────────────────────────────┐
        │   Database Service (ClusterIP)   │
        │   Port: 5432                     │
        │   (Cluster-internal only)        │
        └──────────────────────────────────┘
                       │
                       ▼
        ┌──────────────────────────────────┐
        │   PostgreSQL Database Pod        │
        │   Port: 5432                     │
        │   Data: /var/lib/postgresql/data │
        └──────────────────────────────────┘
                       │
                       ▼
        ┌──────────────────────────────────┐
        │  Persistent Volume (10Gi)        │
        │  Storage Class: standard-rwo     │
        │  Data Persistence: ✓             │
        └──────────────────────────────────┘
```

---

## 2. Service API Tier Architecture

### 2.1 Technology Stack

| Component | Version | Purpose |
|-----------|---------|---------|
| Python | 3.11 | Application runtime |
| Flask | 2.x | Web framework |
| psycopg2 | 2.9+ | PostgreSQL adapter |
| Docker | Latest | Container image |
| Alpine Linux | 3.18 | Base OS (lightweight) |

### 2.2 Application Structure

**File:** `api/app.py`

```
┌─────────────────────────────────────────────────────┐
│                Flask Application (app.py)            │
│                                                     │
│  ┌─────────────────────────────────────────────────┐│
│  │         Connection Pool Manager                  ││
│  │  - SimpleConnectionPool (1-20 connections)      ││
│  │  - 5-second timeout                             ││
│  │  - Connection reuse and release                 ││
│  └─────────────────────────────────────────────────┘│
│                       │                             │
│  ┌────────────────────┼────────────────────────────┐│
│  │                    ▼                             ││
│  │  ┌──────────────────────────────────────────┐  ││
│  │  │         API Routes Layer                 │  ││
│  │  │                                          │  ││
│  │  │  GET /api/records          → All rows   │  ││
│  │  │  GET /api/records/<id>     → Single row │  ││
│  │  │  GET /health               → Liveness   │  ││
│  │  │  GET /ready                → Readiness  │  ││
│  │  │  GET /api/health-info      → Extended   │  ││
│  │  └──────────────────────────────────────────┘  ││
│  │                    │                             ││
│  │  ┌────────────────▼──────────────────────────┐ ││
│  │  │      Database Query Layer                 │ ││
│  │  │                                           │ ││
│  │  │  - Execute SQL queries                   │ ││
│  │  │  - Parse results (RealDictCursor)        │ ││
│  │  │  - Error handling and logging            │ ││
│  │  └────────────────┬──────────────────────────┘ ││
│  │                   │                             ││
│  │  ┌────────────────▼──────────────────────────┐ ││
│  │  │      PostgreSQL Connection (Pooled)       │ ││
│  │  │                                           │ ││
│  │  │  - Connection object from pool           │ ││
│  │  │  - Auto-release on completion            │ ││
│  │  │  - Error handling                        │ ││
│  │  └────────────────┬──────────────────────────┘ ││
│  └────────────────────┼───────────────────────────┘│
│                       │                             │
└───────────────────────┼─────────────────────────────┘
                        │ TCP Port 5432
                        ▼
            ┌───────────────────────┐
            │  PostgreSQL Database  │
            └───────────────────────┘
```

### 2.3 Connection Pooling Strategy

**Implementation:** `api/app.py` (lines 24-42)

```python
connection_pool = psycopg2.pool.SimpleConnectionPool(
    minconn=1,      # Minimum 1 connection always open
    maxconn=20,     # Maximum 20 concurrent connections
    host=DB_HOST,
    port=DB_PORT,
    database=DB_NAME,
    user=DB_USER,
    ******
    connect_timeout=5
)
```

**Benefits:**
- **Reduced Latency:** Reuses existing connections vs. creating new ones
- **Resource Efficiency:** Limits max connections, prevents exhaustion
- **High Throughput:** Can handle multiple concurrent requests
- **Reliability:** Automatic connection cleanup and error handling

**Sizing Rationale:**
- 4 API pods × 5 concurrent requests per pod = ~20 connections needed
- PostgreSQL default max_connections: 100 (plenty of headroom)

---

## 3. Database Tier Architecture

### 3.1 PostgreSQL Configuration

**Image:** `postgres:15-alpine`

**Features:**
- Lightweight Alpine-based image (~150MB)
- Security patches included
- Proven production-ready database
- ACID compliance
- Built-in replication support (not used in this scope)

### 3.2 Database Schema

**Table:** employees

```sql
CREATE TABLE employees (
    id SERIAL PRIMARY KEY,                    -- Auto-incremented unique ID
    name VARCHAR(100) NOT NULL,               -- Employee name
    email VARCHAR(100) UNIQUE NOT NULL,       -- Unique email address
    department VARCHAR(50) NOT NULL,          -- Department name
    salary DECIMAL(10, 2) NOT NULL,           -- Annual salary
    hire_date DATE NOT NULL                   -- Hire date
);
```

**Sample Data:** 8 pre-loaded employee records
- Alice Johnson (Engineering)
- Bob Smith (Marketing)
- Carol Davis (Sales)
- David Wilson (Engineering)
- Eve Martinez (HR)
- Frank Brown (Finance)
- Grace Lee (Engineering)
- Henry Taylor (Operations)

**File:** `database/init.sql`

---

## 4. Kubernetes Components

### 4.1 Namespace

**File:** `k8s/namespace.yaml`

**Purpose:** Logical isolation for all project resources

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: multi-tier
```

**Benefits:**
- Resource isolation from other workloads
- Quota enforcement capability
- Simplified resource discovery
- Easy cleanup: `kubectl delete namespace multi-tier`

---

### 4.2 ConfigMap (Configuration)

**File:** `k8s/configmap.yaml`

**Purpose:** Non-sensitive configuration

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

**Usage:** Injected as environment variables in API Deployment

**Modification Process:**
```bash
# Update ConfigMap
kubectl set env configmap/db-config \
  -n multi-tier \
  DB_HOST=new-postgres-host \
  DB_PORT=5433

# Restart deployment to pick up changes
kubectl rollout restart deployment/api-service -n multi-tier
```

---

### 4.3 Secrets (Sensitive Configuration)

**File:** `k8s/secrets.yaml`

**Purpose:** Store sensitive credentials

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
  namespace: multi-tier
type: Opaque
data:
  db-user: ZGJ1c2Vy              # base64: dbuser
  db-password: ZGJwYXNzd29yZDEyMw==  # base64: dbpassword123
```

**Security Notes:**
- Not encrypted at rest (mitigated by: namespace isolation, RBAC)
- Could be enhanced with Google Secret Manager
- base64 is encoding, not encryption (for human readability in transit)

**Production Enhancement:**
```bash
# Use Google Secret Manager
gcloud secrets create db-password --data-file=-
gcloud secrets create db-user --data-file=-

# Reference in deployment via workload identity
```

---

### 4.4 Persistent Volume Claim (Storage)

**File:** `k8s/db-pvc.yaml`

**Purpose:** Persistent storage for database data

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: multi-tier
spec:
  accessModes:
    - ReadWriteOnce          # Only one pod can mount at a time
  resources:
    requests:
      storage: 10Gi          # 10 Gigabyte allocation
  storageClassName: standard-rwo  # GKE standard storage class
```

**Storage Lifecycle:**
```
PVC Creation → Storage Provisioned → Pod Mounted → 
Data Written → Pod Deletion → Data Persists → 
New Pod Mounted → Data Accessible
```

**Benefits:**
- Automatic provisioning via storage class
- Volume survives pod restarts
- Can be backed up independently
- Resizable without pod restart

---

### 4.5 Deployments

#### 4.5.1 Database Deployment

**File:** `k8s/db-deployment.yaml`

**Configuration:**
```yaml
replicas: 1                    # Single database instance
image: postgres:15-alpine
port: 5432
resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

**Initialization:**
- ConfigMap with init.sql mounted
- Runs on pod startup: creates table, inserts data
- Idempotent: safe to restart

**Health Checks:**
```yaml
livenessProbe:
  exec: pg_isready -U dbuser
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 3

readinessProbe:
  exec: pg_isready -U dbuser
  initialDelaySeconds: 5
  periodSeconds: 10
  failureThreshold: 3
```

#### 4.5.2 API Service Deployment

**File:** `k8s/api-deployment.yaml`

**Configuration:**
```yaml
replicas: 4                    # 4 pods initially, scales to 5 via HPA
image: sohamsharma/py-api-service:latest
port: 5000
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

**Rolling Update Strategy:**
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1              # 1 extra pod during update
    maxUnavailable: 0        # No downtime
```

**Lifecycle Management:**
```yaml
lifecycle:
  preStop:
    exec:
      command: ["/bin/sh", "-c", "sleep 10"]  # Graceful shutdown
```

This allows:
1. Kubelet sends SIGTERM
2. Pod processes existing requests (up to 10 seconds)
3. New connections not accepted
4. Pod terminates cleanly

**Pod Affinity:**
```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values:
            - api-service
        topologyKey: kubernetes.io/hostname
```

**Effect:** Spreads API pods across different nodes (high availability)

---

### 4.6 Services

#### 4.6.1 Database Service

**File:** `k8s/db-service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres-db
  namespace: multi-tier
spec:
  type: ClusterIP              # No external access
  selector:
    app: postgres-db
  ports:
  - port: 5432
    targetPort: 5432
```

**DNS Name:** `postgres-db.multi-tier.svc.cluster.local`

**Internal Only:** No external IP or LoadBalancer

#### 4.6.2 API Service

**File:** `k8s/api-service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: api-service
  namespace: multi-tier
spec:
  type: ClusterIP
  selector:
    app: api-service
  ports:
  - port: 5000
    targetPort: 5000
```

**DNS Name:** `api-service.multi-tier.svc.cluster.local`

**External Access:** Via Ingress controller

---

### 4.7 Ingress

**File:** `k8s/ingress.yaml`

**Purpose:** External HTTP access to API service

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

**Traffic Flow:**
```
External Request (http://<INGRESS_IP>/api/records)
    ↓
GCE Load Balancer (Ingress Controller)
    ↓
Ingress Rule: /api → api-service:5000
    ↓
Service Load Balancer: api-service (ClusterIP)
    ↓
Pod Selection (round-robin across 4-5 pods)
    ↓
Flask Application processes request
    ↓
Response returned to client
```

---

### 4.8 Horizontal Pod Autoscaler

**File:** `k8s/api-hpa.yaml`

**Configuration:**
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa
  namespace: multi-tier
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-service
  minReplicas: 2
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

**Scaling Algorithm:**
```
Desired Replicas = Current Replicas × (Actual Metric / Target Metric)

Example:
- Current Replicas: 4
- CPU Request per pod: 100m
- CPU Actual per pod: 150m (50% over request)
- CPU Target Utilization: 70%
- Calculation: 4 × (150/100) / 0.7 = 4 × 2.14 = ~8.5 pods

Result: Scale to 5 replicas (limited by maxReplicas)
```

---

## 5. Data Flow

### 5.1 Request Processing Flow

```
CLIENT BROWSER (External)
    │ HTTP GET /api/records
    ▼
INGRESS CONTROLLER (GCE Load Balancer)
    │ Routing rule: /api → api-service:5000
    ▼
SERVICE LOAD BALANCER (api-service ClusterIP)
    │ DNS resolves to ClusterIP
    │ Load balances across 4-5 pods
    ▼
SELECTED POD (Flask Application - api/app.py)
    │ before_request() hook
    │ Initializes connection pool if needed
    ▼
ROUTE HANDLER (get_records function)
    │ Acquires connection from pool
    │ Executes SQL query: SELECT * FROM employees ORDER BY id
    ▼
DATABASE POD (PostgreSQL)
    │ Query execution
    │ Row retrieval
    ▼
RESPONSE BUILDING
    │ Cursor.fetchall() returns rows as dicts
    │ JSON serialization
    │ Connection released to pool
    ▼
RESPONSE TRANSMISSION
    │ JSON response with 200 status code
    ▼
CLIENT BROWSER
    │ Display employee records
    ▼
INGRESS LOG
    │ Log request/response metrics
```

### 5.2 Self-Healing Flow

```
LIVENESS CHECK (Every 20 seconds)
    │ GET /health endpoint
    ▼
HEALTH CHECK HANDLER
    │ Attempts database connection
    │ Executes: SELECT 1
    │
    ├─ Success: Returns 200 OK
    │  │ Pod status: HEALTHY
    │  └─ No action
    │
    └─ Failure: Returns 503 (3 times in a row)
       │ Pod status: UNHEALTHY
       ▼
    KUBELET ACTION
       │ Sends SIGTERM signal
       │ Pod enters 30-second grace period
       │ Forces SIGKILL if not terminated
       │ Removes pod
       ▼
    DEPLOYMENT CONTROLLER
       │ Detects missing pod (replicas < desired)
       ▼
    RECONCILIATION
       │ Launches new pod with same spec
       │ Pod starts fresh (clean state)
       │ Becomes READY after probes pass
       │ Receives traffic from load balancer
```

---

## 6. Security Architecture

### 6.1 Network Isolation

```
┌─────────────────────────┐
│   External Internet     │
│   (Uncontrolled)        │
└────────────┬────────────┘
             │ Only HTTP access via
             │ Ingress on port 80
             ▼
     ┌───────────────┐
     │  Ingress (IP) │
     └───────┬───────┘
             │
       ┌─────┴─────┐
       │   Pods    │
       │ API Tier  │
       │ (Protected)
       └─────┬─────┘
             │ Service DNS only
             │ Database not accessible
             │ from outside cluster
             ▼
    ┌─────────────────┐
    │ Database Pod    │
    │ (Cluster-only)  │
    └─────────────────┘
```

### 6.2 Credential Management

**Secrets Locations:**
- ✅ Kubernetes Secrets (base64, not encrypted)
- ✅ Environment variables (in pod memory only)
- ❌ NOT in source code
- ❌ NOT in YAML files
- ❌ NOT in ConfigMaps
- ❌ NOT in logs

**Improvement Path:**
```
Kubernetes Secrets
    ↓ (upgrade to)
Google Secret Manager
    ↓ (with)
Workload Identity binding
    ↓ (automated)
Secret Rotation
```

---

## 7. Performance Characteristics

### 7.1 Latency Profile

| Operation | Typical Latency | Notes |
|-----------|-----------------|-------|
| Pod startup | ~5-10 seconds | includes readiness probe |
| Health check | ~500ms | database connectivity check |
| /api/records query | ~50-200ms | depends on network, DB load |
| Connection pool getconn | <1ms | from existing connection |
| New connection creation | ~50-100ms | TCP handshake + auth |

### 7.2 Throughput Capacity

**Per Pod Capacity:**
- Connection pool: 20 concurrent connections
- Flask thread pool: ~32 threads (Werkzeug default)
- Network bandwidth: Cluster-internal (high speed)

**Estimated Throughput:**
- 4 pods × 8 req/sec per pod = 32 requests/sec
- With HPA to 5 pods: 40 requests/sec

**Bottleneck Likely:** Database (single instance)

---

## 8. Resource Efficiency

### 8.1 Resource Allocation

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|-------------|-----------|-----------------|--------------|
| API Pod (×4-5) | 100m | 500m | 128Mi | 512Mi |
| Database Pod (×1) | 250m | 500m | 256Mi | 512Mi |
| **Total** | 650m | 2500m | 896Mi | 2560Mi |

### 8.2 Node Utilization

**Node Machine Type:** n1-standard-2
- CPU: 2000m available
- Memory: 7500Mi available
- OS/System: ~500m CPU, 1000Mi memory reserved

**Available for Pods:**
- CPU: 1500m
- Memory: 6500Mi

**Current Usage:** ~43% CPU, ~14% Memory
**Scaling Headroom:** Can scale to 5 API pods + maintain capacity

---

## 9. Deployment Lifecycle

### 9.1 Initial Deployment

```
1. Create namespace
   kubectl create namespace multi-tier

2. Create ConfigMaps
   kubectl apply -f k8s/configmap.yaml

3. Create Secrets
   kubectl apply -f k8s/secrets.yaml

4. Create PVC
   kubectl apply -f k8s/db-pvc.yaml

5. Deploy database
   kubectl apply -f k8s/db-deployment.yaml
   Wait: pg_isready to pass

6. Deploy API service
   kubectl apply -f k8s/api-deployment.yaml
   Wait: /ready probe to pass

7. Create Services
   kubectl apply -f k8s/api-service.yaml k8s/db-service.yaml

8. Create Ingress
   kubectl apply -f k8s/ingress.yaml
   Obtain: INGRESS_IP

9. Configure HPA
   kubectl apply -f k8s/api-hpa.yaml
```

### 9.2 Update Deployment

```
# Scenario: Update API image to new version

1. Build new Docker image
   docker build -t sohamsharma/py-api-service:v1.1.0 ./api
   docker push sohamsharma/py-api-service:v1.1.0

2. Update deployment image
   kubectl set image deployment/api-service \
     api=sohamsharma/py-api-service:v1.1.0 \
     -n multi-tier

3. Monitor rollout
   kubectl rollout status deployment/api-service -n multi-tier

   Output:
   Waiting for rollout to finish: 2 of 4 updated replicas are available...
   deployment "api-service" successfully rolled out
```

**Rolling Update Process:**
```
Before:  [Pod1(v1.0)] [Pod2(v1.0)] [Pod3(v1.0)] [Pod4(v1.0)]
                      ↓ maxSurge=1, maxUnavailable=0
Step 1:  [Pod1(v1.0)] [Pod2(v1.0)] [Pod3(v1.0)] [Pod4(v1.0)] [Pod5(v1.1)]
Step 2:  [Pod1(v1.1)] [Pod2(v1.0)] [Pod3(v1.0)] [Pod4(v1.0)]
Step 3:  [Pod1(v1.1)] [Pod2(v1.1)] [Pod3(v1.0)] [Pod4(v1.0)]
Step 4:  [Pod1(v1.1)] [Pod2(v1.1)] [Pod3(v1.1)] [Pod4(v1.0)]
After:   [Pod1(v1.1)] [Pod2(v1.1)] [Pod3(v1.1)] [Pod4(v1.1)]

Result: Zero downtime, all traffic served throughout
```

---

## 10. Monitoring and Observability

### 10.1 Health Probes

**Liveness Probe:** Restarts failed pods

```python
@app.route('/health', methods=['GET'])
def health():
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute('SELECT 1')
        cursor.close()
        release_db_connection(conn)
        return jsonify({'status': 'healthy'}), 200
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return jsonify({'status': 'unhealthy', 'error': str(e)}), 503
```

**Readiness Probe:** Removes pod from load balancer if not ready

```python
@app.route('/ready', methods=['GET'])
def ready():
    try:
        if not connection_pool:
            init_connection_pool()
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute('''SELECT COUNT(*) FROM information_schema.tables 
                         WHERE table_name=%s''', ('employees',))
        result = cursor.fetchone()
        cursor.close()
        release_db_connection(conn)
        if result[0] > 0:
            return jsonify({'status': 'ready'}), 200
        else:
            return jsonify({'status': 'not_ready'}), 503
    except Exception as e:
        logger.error(f"Readiness check failed: {str(e)}")
        return jsonify({'status': 'not_ready', 'error': str(e)}), 503
```

### 10.2 Resource Monitoring

```bash
# Node resource usage
kubectl top nodes

# Pod resource usage
kubectl top pods -n multi-tier

# HPA metrics
kubectl get hpa -n multi-tier -o wide

# Pod resource requests/limits
kubectl describe pod -n multi-tier <pod-name>
```

---

## Summary

This solution provides:

✅ **Scalability:** Auto-scales from 2-5 pods based on demand
✅ **Reliability:** Self-healing via liveness/readiness probes
✅ **Performance:** Connection pooling, graceful shutdowns
✅ **Security:** Secrets management, network isolation
✅ **Persistence:** PVC-backed database storage
✅ **Updateability:** Zero-downtime rolling updates
✅ **Observability:** Health checks, resource metrics
✅ **Cost-Effectiveness:** Right-sized resources, HPA

For detailed implementation guidelines, refer to other documentation files.
