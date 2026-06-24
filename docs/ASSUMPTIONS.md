# Assumptions

This document outlines all assumptions made during the design and implementation of the multi-tier Kubernetes architecture project.

---

## 1. Deployment Environment Assumptions

### 1.1 Kubernetes Cluster

**Assumption:** The project assumes deployment on a managed Kubernetes service with standard features.

- **GKE (Google Kubernetes Engine):** Primary target platform
- **API Version:** Kubernetes 1.24+ (supports networking.k8s.io/v1 Ingress)
- **Node Count:** Minimum 3 nodes for production workload distribution
- **Node Machine Type:** n1-standard-2 or equivalent (2 vCPU, 7.5GB RAM)

**Rationale:** GCP services were specified in requirements; GKE is the appropriate choice.

---

### 1.2 Storage Class

**Assumption:** Default storage class is available in the cluster.

```bash
# Verify storage class exists
kubectl get storageclass
# Expected: default or gp2 storage class available
```

**Details:**
- PVC (Persistent Volume Claim) created without specifying storageClassName
- Assumes cluster has default storage provisioner
- GKE provides automatic provisioning via standard or premium-rwo classes

**Fallback:** If no default storage class, specify explicitly:
```yaml
storageClassName: standard-rwo  # For GKE
```

---

### 1.3 Ingress Controller

**Assumption:** An Ingress controller is installed and operational.

- **GKE Default:** Ingress controller automatically deployed
- **Alternative:** Could use nginx-ingress, traefik, or other controllers
- **Note:** Ingress resource only creates configuration; controller must exist

**Verification:**
```bash
kubectl get ingressclass
# Expected: nginx or gce ingress class
```

---

## 2. Application Assumptions

### 2.1 Python Flask Application

**Assumption:** Flask application can be packaged and deployed via Docker.

- **Python Version:** 3.11
- **Framework:** Flask (lightweight, production-ready)
- **Database Driver:** psycopg2 (standard PostgreSQL connector)
- **Port:** 5000 (Flask default)

**No Assumption About:**
- Specific framework features (no complex ORM required)
- High-throughput requirements (simple in-memory connection pooling sufficient)
- Authentication/Authorization (beyond database connection security)

---

### 2.2 Database Engine

**Assumption:** PostgreSQL 15 is suitable for this workload.

- **Database:** PostgreSQL (open-source, reliable, widely-supported)
- **Version:** 15-alpine (small Docker image, security updates)
- **Port:** 5432 (standard PostgreSQL port)
- **Connections:** Single database instance (not replicated)

**No Scaling Assumption:**
- Single PostgreSQL pod meets requirement
- No read replicas configured
- No sharding implemented

---

## 3. Data Assumptions

### 3.1 Data Volume

**Assumption:** The dataset is small (8 employee records).

- **Table Size:** Single employees table with ~8 rows
- **Storage Requirement:** < 1MB actual data
- **PVC Size Allocated:** 10Gi (conservative buffer for growth)

**Scaling Consideration:** For larger datasets, increase PVC size or implement archival.

---

### 3.2 Data Integrity

**Assumption:** Data integrity requirements are standard (ACID compliance via PostgreSQL).

- **ACID Compliance:** PostgreSQL provides full ACID guarantees
- **Backup Strategy:** Assumed external backup tool handles backups
- **No Real-time Replication:** Not required for this project scope

**Note:** Production should implement:
- Regular backups to Cloud Storage (Google Cloud Storage)
- Point-in-time recovery capability
- Database snapshots

---

## 4. Security Assumptions

### 4.1 Secrets Management

**Assumption:** Kubernetes Secrets are adequate for this non-production environment.

- **Current Implementation:** base64-encoded Secrets
- **Production Recommendation:** Use Google Secret Manager or HashiCorp Vault

```bash
# Current approach (development)
kubectl create secret generic db-credentials --from-literal=db-user=dbuser --from-literal=db-******

# Production approach would use:
# - Workload Identity binding
# - Secret Manager for credential storage
# - Automatic secret rotation
```

---

### 4.2 Network Security

**Assumption:** Kubernetes NetworkPolicy is not required for this scope.

- **Current:** All pods in multi-tier namespace can communicate
- **Assumption:** Network security handled at cluster/namespace level
- **Note:** Production should implement NetworkPolicy for:
  - Only allow api-service to initiate connections to postgres-db
  - Deny all other inter-pod communication

**Production Implementation:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: postgres-network-policy
  namespace: multi-tier
spec:
  podSelector:
    matchLabels:
      app: postgres-db
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: api-service
    ports:
    - protocol: TCP
      port: 5432
```

---

### 4.3 TLS/HTTPS

**Assumption:** TLS termination handled by Ingress controller (external configuration).

- **Current Implementation:** HTTP (port 80)
- **Ingress Configuration:** TLS certificate management external to this project
- **GKE Default:** Supports managed TLS via Google-managed certificates

**Production Configuration:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    cert.gcp.sh/managed-by: "gce"
    ingress.gcp.kubernetes.io/pre-shared-cert: "your-ssl-cert"
spec:
  tls:
  - hosts:
    - api.example.com
    secretName: api-tls-secret
  rules:
  - host: api.example.com
```

---

## 5. Networking Assumptions

### 5.1 Service-to-Service Communication

**Assumption:** Kubernetes DNS service resolution is available.

- **DNS Service:** kube-dns or CoreDNS running in cluster
- **Service Names:** Resolvable within cluster namespace
- **FQDN:** `postgres-db.multi-tier.svc.cluster.local`

**Assumption Details:**
- No service mesh (Istio, Linkerd) required for this scope
- Simple Kubernetes DNS sufficient
- Connection pooling handled at application level

---

### 5.2 External Access

**Assumption:** External access only via Ingress controller.

- **Database:** NOT accessible externally (ClusterIP service only)
- **API Service:** Accessible via Ingress IP/hostname
- **No Direct Pod Access:** User cannot directly access pod IPs

---

## 6. Operational Assumptions

### 6.1 Deployment Process

**Assumption:** Standard Kubernetes deployment workflow.

- **Tool:** kubectl command-line tool
- **Manifest Location:** `k8s/` directory containing all YAML files
- **Namespace:** multi-tier (created before deployment)
- **Image Registry:** Docker Hub (public images)

**Deployment Sequence:**
1. Create namespace
2. Create Secrets
3. Create ConfigMaps
4. Create PVC
5. Deploy database
6. Deploy API service
7. Create Services
8. Create Ingress
9. Configure HPA

---

### 6.2 Monitoring and Logging

**Assumption:** Basic Kubernetes monitoring is available.

- **Metrics Server:** Installed for HPA (required for CPU/Memory metrics)
- **Logging:** Standard pod logs via kubectl logs
- **No External Monitoring:** Prometheus/Grafana not required
- **No Log Aggregation:** ELK, Splunk, or Cloud Logging not configured

**Current Capabilities:**
```bash
# View resource usage
kubectl top pods -n multi-tier
kubectl top nodes

# View HPA status
kubectl get hpa -n multi-tier

# View pod logs
kubectl logs -n multi-tier deployment/api-service
```

**Production Assumptions:** Google Cloud Operations (formerly Stackdriver) for logs and metrics.

---

### 6.3 Pod Restart Behavior

**Assumption:** Pod restart policy is "Always" (default).

- **Liveness Probe Failures:** Pod automatically restarted
- **Node Failure:** Pods rescheduled to other nodes
- **Manual Deletion:** Pod recreated by Deployment controller

---

## 7. Performance Assumptions

### 7.1 Connection Pooling

**Assumption:** Connection pool size (1-20) is appropriate for workload.

```python
connection_pool = psycopg2.pool.SimpleConnectionPool(
    1,   # Minimum connections always open
    20,  # Maximum connections allowed
    ...
)
```

**Rationale:**
- Minimum: 1 (enough for startup, one request can establish)
- Maximum: 20 (4 API pods × 5 concurrent connections average)
- Conservative estimate prevents connection exhaustion

**Assumption:** Database can handle 20 connections from each API pod.
- PostgreSQL default max_connections: 100
- With 4 API pods: ~80 connections max, well below limit

---

### 7.2 Request Latency

**Assumption:** Average request latency < 500ms acceptable for self-healing probe.

- **Probe Timeout:** 5 seconds
- **Failure Threshold:** 3 consecutive failures before restart
- **Assumption:** Network latency and query execution < 1 second average

---

### 7.3 Database Query Performance

**Assumption:** Query performance is acceptable without indexing.

- **Query:** `SELECT * FROM employees ORDER BY id ASC`
- **Records:** 8 rows (full table scan very fast)
- **Index:** Not needed for this dataset size

**Production:** Would add:
```sql
CREATE INDEX idx_employees_id ON employees(id);
CREATE INDEX idx_employees_email ON employees(email);
```

---

## 8. Scaling Assumptions

### 8.1 HPA Behavior

**Assumption:** Metrics Server provides CPU and memory metrics within 30 seconds.

- **Metric Collection:** 15-second granularity (default)
- **Scaling Decision:** Every 15 seconds HPA evaluates metrics
- **Cooldown Period:** 3 minutes between scale-down events (default)

**Assumptions:**
- Load generation affects metrics within 1-2 minutes
- Pod startup time: ~10 seconds
- Database handles scale to 5 API pods

---

### 8.2 Resource Availability

**Assumption:** Cluster has sufficient resources to scale to 5 API pods.

- **Per Pod Request:** 100m CPU, 128Mi memory
- **Max 5 Pods:** 500m CPU, 640Mi memory total
- **Cluster Assumption:** Node has 2000m CPU, 7500Mi memory minimum

**Sizing:**
- 3 nodes × 2 vCPU = 6 vCPU (6000m) available
- 3 nodes × 7.5GB = 22.5GB available
- Sufficient for 5 API pods + 1 database pod

---

## 9. Cost Assumptions

### 9.1 Cluster Configuration

**Assumption:** Standard GKE cluster pricing applies.

- **Node Type:** n1-standard-2
- **Count:** 3 nodes (for production availability)
- **Regional Cluster:** Zone-based (recommended)
- **Persistence:** Standard-rwo storage class ($/GB/month)

**Cost Components:**
- Node compute costs
- Storage costs (PVC allocation)
- Network egress costs
- Ingress controller costs (GCE Load Balancer)

**Assumption:** Cluster already exists; per-pod costs documented separately.

---

### 9.2 Resource Efficiency

**Assumption:** Resources can be optimized based on actual utilization.

- **Current Requests:** Conservative (may be over-provisioned)
- **Monitoring:** Will measure actual CPU/memory usage
- **Optimization:** Can reduce requests based on metrics
- **Timeline:** After 1-2 weeks of production monitoring

**Example:** If CPU actual usage is 20m (vs 100m request):
- Could reduce request to 30m
- Improves bin-packing, allows more pods per node
- Reduces cluster size requirement

---

## 10. Compatibility Assumptions

### 10.1 Kubernetes API Versions

**Assumption:** Kubernetes 1.24+ supports all API versions used.

- **apps/v1:** Deployment, ReplicaSet, StatefulSet (stable since 1.16)
- **v1:** Service, ConfigMap, Secret, PVC, Namespace (stable since 1.0)
- **networking.k8s.io/v1:** Ingress (stable since 1.19)
- **autoscaling/v2:** HPA (stable since 1.23)

**Compatibility:** All manifests backward-compatible to Kubernetes 1.19+

---

### 10.2 Docker Image Compatibility

**Assumption:** Docker images available and compatible.

- **Python Image:** python:3.11 (official, widely-available)
- **PostgreSQL Image:** postgres:15-alpine (official, widely-available)
- **Registry:** Docker Hub (publicly accessible)

**No Assumptions About:**
- Private registry setup
- Image signing or security scanning
- Container scanning vulnerabilities

---

## 11. Development vs Production Assumptions

### 11.1 This Implementation Is Suitable For:

✅ Development environment
✅ Testing and learning Kubernetes concepts
✅ Non-critical demo/prototype workloads
✅ Small dataset (< 1GB)
✅ Moderate traffic (< 1000 req/sec)

### 11.2 This Implementation Requires Enhancement For Production:

Production deployment would require:
- Secret rotation and external Secret Manager
- TLS/HTTPS encryption
- Network policies and pod security policies
- Backup and disaster recovery
- Multi-pod database (StatefulSet with replication)
- Load testing and performance validation
- Comprehensive monitoring and alerting
- Audit logging and compliance
- Auto-scaling node count (cluster autoscaler)
- Pod disruption budgets

---

## 12. Documentation Assumptions

### 12.1 Audience

**Assumption:** Documentation targets:
- DevOps engineers familiar with Kubernetes
- Cloud architects evaluating the solution
- Students learning Kubernetes concepts
- Operators deploying/maintaining the system

**Not Assumed:**
- Zero Kubernetes knowledge
- Requirement for super-detailed step-by-step instructions
- Graphical UI walkthroughs

---

### 12.2 Supported Platforms

**Assumption:** Primary platform is GKE (Google Kubernetes Engine).

**Documentation covers:**
- GKE-specific features and commands
- Google Cloud Platform services
- gcloud CLI usage

**Adaptable to:**
- Other managed Kubernetes (AKS, EKS)
- On-premises Kubernetes
- Minikube for local testing

---

## Summary

All assumptions have been documented to ensure:

1. **Clear Context:** Readers understand design decisions
2. **Production Awareness:** Notes on what needs to change for production
3. **Environment Clarity:** What Kubernetes features are required
4. **Scalability Limits:** When assumptions break down
5. **Upgrade Path:** How to evolve from development to production

For specific questions about design choices, refer to the **Solution Overview** documentation.
