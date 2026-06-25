# Solution Overview and Architecture

## System Architecture

### High-Level Diagram

```
┌──────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                     │
│                  (multi-tier namespace)                   │
├──────────────────────────────────────────────────────────┤
│                                                            │
│  ┌────────────────────────────────────────────────────┐  │
│  │              External Access Layer                  │  │
│  ├────────────────────────────────────────────────────┤  │
│  │  Ingress (api-ingress)  → LoadBalancer Service    │  │
│  │                            (api-service:80)        │  │
│  └────────────────────────────────────────────────────┘  │
│                          ↓                                │
│  ┌────────────────────────────────────────────────────┐  │
│  │            Service API Tier (4 replicas)           │  │
│  ├────────────────────────────────────────────────────┤  │
│  │  Pod 1: Flask API (5000)  [ConfigMap + Secrets]   │  │
│  │  Pod 2: Flask API (5000)                           │  │
│  │  Pod 3: Flask API (5000)  [HPA: 2-5 replicas]     │  │
│  │  Pod 4: Flask API (5000)  [CPU/Memory based]      │  │
│  │                                                    │  │
│  │  Features:                                         │  │
│  │  • Connection pooling to DB                        │  │
│  │  • Health/Readiness probes                         │  │
│  │  • Rolling updates (zero downtime)                 │  │
│  │  • Pod anti-affinity for distribution              │  │
│  │  • Resource limits/requests                        │  │
│  └────────────────────────────────────────────────────┘  │
│                          ↓                                │
│  ┌────────────────────────────────────────────────────┐  │
│  │          Database Service (ClusterIP)              │  │
│  │          postgres-db:5432 (internal only)          │  │
│  └────────────────────────────────────────────────────┘  │
│                          ↓                                │
│  ┌────────────────────────────────────────────────────┐  │
│  │        Database Tier (1 replica - stateful)        │  │
│  ├────────────────────────────────────────────────────┤  │
│  │  Pod: PostgreSQL 15 (5432)                         │  │
│  │                                                    │  │
│  │  Features:                                         │  │
│  │  • 10Gi Persistent Volume (ReadWriteOnce)          │  │
│  │  • Health probes (pg_isready)                      │  │
│  │  • Database initialization script (ConfigMap)      │  │
│  │  • Credentials via Secrets                         │  │
│  │  • 8 pre-loaded employee records                   │  │
│  └────────────────────────────────────────────────────┘  │
│                          ↓                                │
│  ┌────────────────────────────────────────────────────┐  │
│  │     Persistent Storage (10Gi PVC)                  │  │
│  │     /var/lib/postgresql/data → Cloud Disk          │  │
│  └────────────────────────────────────────────────────┘  │
│                                                            │
└──────────────────────────────────────────────────────────┘
```

## Component Interaction Flow

### Request Processing Flow

```
1. Client Request
   └─→ Ingress (External IP)
       └─→ LoadBalancer Service (api-service:80)
           └─→ API Pod (5000)
               ├─→ Request validation
               ├─→ Connection pool checkout
               ├─→ Database query execution
               │   └─→ PostgreSQL (5432) via ClusterIP Service
               │       └─→ Data retrieval from PVC
               ├─→ Connection pool return
               └─→ Response formatting and return
```

## Kubernetes Resources

### Namespace
- **Name**: multi-tier
- **Isolation**: Provides logical separation of resources
- **RBAC**: Default service account available

### ConfigMaps
#### db-config
- **Purpose**: Non-sensitive database configuration
- **Data**:
  - DB_HOST: postgres-db
  - DB_PORT: 5432
  - DB_NAME: microservices_db
- **Usage**: Mounted as environment variables in API pods
- **Editability**: Can be updated without redeploying pods (requires pod restart)

#### init-script
- **Purpose**: Database schema initialization
- **Data**: SQL script with CREATE TABLE and INSERT statements
- **Usage**: Mounted as volume in /docker-entrypoint-initdb.d
- **Execution**: Automatically runs on database pod startup

### Secrets
#### db-credentials
- **Type**: Opaque
- **Storage**: Base64 encoded by Kubernetes
- **Data**:
  - db-user: dbuser
  - db-password: SecurePassword123!@#
- **Usage**: Environment variables in API and Database pods
- **Security**: Credentials not visible in manifests (use stringData)

### Services

#### api-service (LoadBalancer)
- **Type**: LoadBalancer
- **Port Mapping**: 80 → 5000
- **Selector**: app=api-service
- **External Access**: Yes (cloud provider load balancer)
- **Use Case**: External API access

#### postgres-db (ClusterIP)
- **Type**: ClusterIP
- **Port**: 5432 (standard PostgreSQL)
- **Selector**: app=postgres-db
- **External Access**: No (cluster-internal only)
- **DNS Name**: postgres-db.multi-tier.svc.cluster.local
- **Use Case**: Internal database access

### Deployments

#### api-service Deployment
- **Replicas**: 4 (base replicas, can scale with HPA)
- **Strategy**: RollingUpdate
  - maxSurge: 1 (one extra pod during update)
  - maxUnavailable: 0 (no pods down during update)
- **Image**: sohamsharma/py-api-service:latest
- **Image Pull Policy**: Always (ensures latest image)
- **Probes**:
  - Liveness: /health endpoint (20s period)
  - Readiness: /ready endpoint (10s period)
- **Lifecycle Hooks**:
  - preStop: 10-second sleep for graceful shutdown
- **Affinity**: Pod anti-affinity (prefer different nodes)
- **Environment**: ConfigMap + Secrets

#### postgres-db Deployment
- **Replicas**: 1 (stateful, no scaling)
- **Image**: postgres:15-alpine
- **Volume**: PersistentVolumeClaim (postgres-pvc, 10Gi)
- **Init Script**: ConfigMap mount at /docker-entrypoint-initdb.d
- **Probes**:
  - Liveness: pg_isready (10s period)
  - Readiness: pg_isready (10s period)

### PersistentVolumeClaim
- **Name**: postgres-pvc
- **Size**: 10Gi
- **Access Mode**: ReadWriteOnce
- **Storage Class**: standard
- **Provider**: Cloud provider's default storage backend

### Horizontal Pod Autoscaler (HPA)
- **Target**: api-service Deployment
- **Metrics**:
  - CPU: 50% utilization threshold
  - Memory: 70% utilization threshold
- **Replica Bounds**: min=2, max=5
- **Scale-Up Behavior**:
  - Stabilization: 30 seconds
  - Policy: 100% increase per 30 seconds
  - Secondary policy: +2 pods per 60 seconds
- **Scale-Down Behavior**:
  - Stabilization: 300 seconds
  - Policy: 50% decrease per 60 seconds

### Ingress
- **Type**: Ingress
- **Ingress Class**: gce (Google Cloud Engine)
- **Routing**:
  - Path: / (all traffic)
  - Backend: api-service:80
- **Features**: GCP-managed SSL/HTTP(S) load balancer

## Data Flow Architecture

### Database Initialization

```
Kubernetes Cluster Start
  ├─→ ConfigMap (init-script) created
  ├─→ PersistentVolume provisioned
  ├─→ PersistentVolumeClaim bound to PV
  └─→ postgres-db Pod starts
      ├─→ Init-script mounted at /docker-entrypoint-initdb.d
      ├─→ PostgreSQL starts
      └─→ Init-script executes:
          ├─→ CREATE TABLE employees
          └─→ INSERT 8 sample records
```

### API Request Processing

```
Client HTTP Request → Ingress → LoadBalancer → api-service Pod
  ├─→ Flask receives request
  ├─→ Before request hook:
  │   └─→ Initialize connection pool (if not already done)
  ├─→ Route handler (e.g., /api/records)
  │   ├─→ Get connection from pool
  │   ├─→ Create cursor
  │   ├─→ Execute SQL query
  │   ├─→ Convert results to JSON
  │   ├─→ Close cursor
  │   └─→ Return connection to pool
  └─→ Response sent back through ingress
```

### Connection Pool Management

```
Connection Pool (min=1, max=20)
  ├─→ Lazy initialization on first request
  ├─→ Connection reuse across requests
  ├─→ Timeout: 5 seconds for new connections
  ├─→ Error handling: 503 Service Unavailable if pool unavailable
  └─→ Graceful closing on pod termination
```

## Self-Healing and High Availability

### Liveness Probes
- **API Service**: HTTP GET /health
  - Checks database connectivity
  - Failure: Pod restart
  - Prevents hung processes from serving traffic

### Readiness Probes
- **API Service**: HTTP GET /ready
  - Verifies employees table exists
  - Failure: Pod removed from load balancer
  - Ensures correct initialization

- **Database**: pg_isready command
  - Checks PostgreSQL accepting connections
  - Failure: Pod restart

### Self-Healing Scenarios

#### API Pod Failure
1. Pod crashes or becomes unhealthy
2. Liveness probe detects issue
3. Kubernetes automatically restarts pod
4. Readiness probe verifies it's ready
5. LoadBalancer routes traffic to healthy pods

#### Database Pod Failure
1. Pod crashes or becomes unhealthy
2. Liveness probe detects issue
3. Kubernetes automatically restarts pod
4. Volume mount restored from PVC
5. Data persists (no loss)
6. Init-script not re-executed (data already exists)

### Scaling Behavior

#### Scale-Up
1. CPU/Memory usage exceeds thresholds (50%/70%)
2. HPA detects metrics via metrics-server
3. New pods created up to max=5
4. Pods created from same deployment spec
5. Load balanced across new replicas

#### Scale-Down
1. Resource utilization decreases
2. HPA scales down after 300s stabilization
3. Max 50% decrease per 60 seconds
4. Connections drained via preStop hook
5. Pods gracefully terminated

## Rolling Updates and Deployments

### Update Process

```
kubectl apply -f api-deployment.yaml

1. New ReplicaSet created with updated image
2. maxSurge: 1 → one additional pod allowed (total: 5)
3. One new pod starts with new image
4. Readiness probe verifies new pod is ready
5. LoadBalancer routes to new pod
6. One old pod terminated
7. Process repeats until all pods updated
8. Final result: 4 pods with new image
9. Zero downtime during update
10. Fast rollback available if needed
```

## Security Architecture

### Data Security
- **Secrets Management**:
  - db-password: Stored in Kubernetes Secrets (base64 encoded)
  - Not visible in deployment manifests
  - Injected as environment variables at runtime
  
- **ConfigMap**: Non-sensitive data only
  - Database host, port, name
  - Init script (public schema definition)

### Network Security
- **Internal Service**: postgres-db only accessible within cluster
- **External Service**: api-service exposed via LoadBalancer
- **Service Names**: Used instead of pod IPs
- **DNS Resolution**: Kubernetes DNS handles service discovery

### Pod Security
- **Non-root User**: API runs as appuser (UID 1000)
- **Resource Limits**: Prevents resource exhaustion attacks
- **Health Checks**: Detects and restarts compromised pods

## Performance Characteristics

### Connection Pooling Benefits
- Connection reuse reduces overhead
- Faster response times for subsequent queries
- Protects database from connection exhaustion
- SimpleConnectionPool appropriate for this workload

### Scaling Characteristics
- **Linear scaling**: Additional replicas handle proportional load increase
- **CPU-driven**: Scaling primarily responsive to CPU usage
- **Memory-driven**: Secondary scaling trigger
- **Response**: Fast scale-up (30s), conservative scale-down (300s)

### Resource Utilization
- **API Pods**: 100m-500m CPU, 128Mi-512Mi Memory
- **Database Pod**: 250m-500m CPU, 256Mi-512Mi Memory
- **Storage**: 10Gi for database persistent storage

## Deployment Topology

### Multi-Node Deployment
- **Pod Anti-affinity**: Preferred distribution across nodes
- **Load Distribution**: Load balanced across nodes
- **Resilience**: Failure of single node affects subset of pods
- **Optimal**: 4 API pods across minimum 2-3 nodes

### Storage Topology
- **PVC Binding**: Bound to single cloud storage location
- **Zone Availability**: May be zone-specific
- **Backup Strategy**: Not implemented (cloud provider handles)

## Monitoring and Observability

### Built-in Metrics
- **Health Endpoints**: /health, /ready, /api/health-info
- **Prometheus Annotations**: Configured in deployment
- **Kubernetes Metrics**: CPU, Memory via metrics-server

### Logging
- **Container Logs**: stdout/stderr captured by Kubernetes
- **Access**: via `kubectl logs deployment/api-service -n multi-tier`
- **Level**: INFO for application events, ERROR for failures

### Alerting
- **Probe-based**: Liveness/readiness probes trigger restarts
- **Manual Monitoring**: Check HPA status, pod counts
- **Observability**: Requires external monitoring (Prometheus, etc.)

## Cost Implications

### Resource Requests
- **Guaranteed capacity**: Reserved for pods
- **Billing basis**: Cloud providers bill based on requests
- **Efficiency**: Right-sized requests reduce costs

### Scaling Impact
- **Fixed cost**: Base 4 API pods + 1 database
- **Variable cost**: Additional replicas with HPA
- **Peak handling**: 5 API pods maximum
- **Off-peak**: Scale down to 2 replicas

### Storage Cost
- **Persistent**: 10Gi always allocated
- **Growth**: No automatic deletion of old data
- **Optimization**: Monitoring and cleanup policies needed
