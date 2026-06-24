# Assumptions and Design Decisions

## Deployment Environment

### Kubernetes Cluster
- **Provider**: Google Kubernetes Engine (GKE) or any Kubernetes 1.20+ cluster
- **Node Type**: General-purpose compute instances (e.g., n1-standard-2)
- **Number of Nodes**: Minimum 3 nodes for production resilience
- **Networking**: Standard Kubernetes networking with DNS enabled
- **Storage**: Standard block storage available (Google Persistent Disk or equivalent)

### Container Registry
- **Docker Hub**: Assumed to be accessible and configured with credentials
- **Image Pull Policy**: Always (for latest images in development)
- **Internet Access**: Cluster nodes can pull images from Docker Hub

## Architectural Assumptions

### Single Database Instance
- **No Database Clustering**: Only one PostgreSQL instance is deployed
- **No Multi-Master Replication**: Single point of database service
- **Acceptable for**: Development, testing, and demonstration purposes
- **Production Consideration**: Multi-replica PostgreSQL should be used for HA

### Stateless API Service
- **Session Management**: No session affinity required
- **Load Distribution**: Requests can be distributed across all replicas
- **State Location**: All application state is in the database
- **Scaling**: Horizontal scaling is straightforward

### Network Architecture
- **Flat Network**: All pods communicate on the same network
- **Service Discovery**: Kubernetes DNS (kube-dns) is available
- **No Network Policies**: Assuming no advanced network segmentation
- **Internal Communication**: Service names (postgres-db) used instead of IPs

## Technology Choices

### Python Flask Framework
- **Assumption**: Python 3.11 is available and preferred
- **Framework**: Flask is lightweight and suitable for this microservice
- **Alternative**: Could use FastAPI, Django, etc.
- **ASGI Server**: Gunicorn is used as the WSGI server
- **Workers**: 4 worker processes for concurrent request handling

### PostgreSQL Database
- **Version**: PostgreSQL 15 (latest stable)
- **Alpine Image**: Minimal image for reduced resource usage
- **Initialization**: SQL script in ConfigMap for schema setup
- **No ORM**: Direct psycopg2 connection for simplicity

### Connection Pooling
- **Implementation**: psycopg2 SimpleConnectionPool
- **Min Connections**: 1 (suitable for development)
- **Max Connections**: 20 (reasonable for load testing)
- **Timeout**: 5 seconds for connection establishment
- **Production Adjustment**: May need to increase for high-concurrency scenarios

## Kubernetes Assumptions

### Resource Availability
- **CPU**: Sufficient CPU quotas for the requested resources
- **Memory**: Sufficient RAM for minimum 8 pods (4 API + 1 DB + HPA room)
- **Disk**: 10Gi available for database PVC
- **Network**: No network quotas or bandwidth limitations

### Ingress Controller
- **Type**: GCE Ingress Controller (Google Cloud Load Balancer)
- **Service Mesh**: No service mesh (Istio, Linkerd, etc.) assumed
- **TLS**: Not configured (assumed for internal or development use)
- **Production Consideration**: TLS should be added with proper certificates

### Pod Security
- **User Permissions**: Container runs as non-root user (appuser)
- **Security Policies**: No Pod Security Policy enforced
- **RBAC**: Minimal RBAC configuration assumed

## Configuration Assumptions

### Environment Variables
- **Database Config**: Via ConfigMap (non-sensitive data)
- **Credentials**: Via Kubernetes Secrets (password, username)
- **Application Config**: Via environment variables (Flask app)
- **No Config Files**: Configuration not stored in container images

### Secrets Management
- **Kubernetes Native**: Using Kubernetes Secrets (base64 encoded, at-rest encryption)
- **Production**: Should use external secret management (HashiCorp Vault, Cloud Secret Manager)
- **Secret Creation**: Manual creation via YAML files with stringData
- **Rotation**: No automated secret rotation configured

## Data and Testing Assumptions

### Test Data
- **Sample Records**: 8 pre-loaded employee records for testing
- **Static Schema**: Single employees table with fixed structure
- **No Migrations**: Schema is static and created on initialization
- **Data Retention**: Data persists across pod restarts via PVC

### Testing Scope
- **Unit Tests**: Focus on API endpoints and database connectivity
- **Integration Tests**: API to database communication
- **Load Testing**: Manual via HPA testing or external load tools
- **No E2E**: No comprehensive end-to-end test suite included

## Performance and Scaling Assumptions

### Horizontal Pod Autoscaling
- **Metric Type**: Resource-based (CPU and Memory)
- **No Custom Metrics**: Assuming metrics-server is available in cluster
- **Scale-Up Delay**: Fast scale-up (30 seconds) for responsive scaling
- **Scale-Down Delay**: Longer scale-down (300 seconds) to prevent flapping
- **Max Replicas**: 5 API pods as the reasonable upper limit

### Connection Pool Behavior
- **Lazy Initialization**: Connection pool initialized on first request
- **Error Handling**: Connection errors result in 503 Service Unavailable
- **Connection Timeout**: 5 seconds timeout for connection establishment

## Operational Assumptions

### Logging
- **Method**: Standard output (containers logs via kubectl logs)
- **Format**: Plain text logs with timestamps
- **Aggregation**: Not configured (would be done by cluster logging solution)
- **No External Logging**: ELK, Splunk, etc. not assumed

### Monitoring
- **Health Checks**: Kubernetes liveness and readiness probes
- **Annotations**: Prometheus scrape annotations added but no Prometheus assumed
- **Metrics**: Basic HTTP health metrics only
- **Dashboards**: Not included in deployment

### Upgrades and Maintenance
- **Rolling Updates**: Zero-downtime deployments with rolling update strategy
- **Graceful Shutdown**: 10-second pre-stop hook for connection draining
- **Database Migrations**: None required (static schema)
- **Backward Compatibility**: Assumed across API versions

## Security Assumptions

### Container Security
- **Privilege Level**: Non-root user (appuser, UID 1000)
- **Read-Only Root FS**: Not enforced
- **Capabilities**: Default Linux capabilities allowed
- **No Security Context**: Limited Pod Security Context defined

### Network Security
- **No Network Policies**: Assuming no microsegmentation required
- **Service-to-Service**: All communication within cluster
- **External Access**: Via LoadBalancer service or Ingress only
- **TLS**: Not implemented (assumed for development environment)

### Data Security
- **At-Rest Encryption**: Not configured (varies by cloud provider)
- **Encryption**: Relies on cloud provider's disk encryption
- **Secrets Encoding**: Base64 (not true encryption)
- **Production**: Use etcd encryption and external secret management

## Cost Optimization Assumptions

### Resource Right-Sizing
- **Development Assumption**: Current resource requests are conservative
- **Monitoring Required**: Actual usage should be measured
- **Adjustment**: Resources can be reduced if usage is lower than allocated
- **Buffer**: Some overhead included for burst capacity

### Scaling Efficiency
- **Cluster Utilization**: Assuming cluster has sufficient capacity
- **Node Packing**: No bin-packing optimization assumed
- **Spot Instances**: Not utilized (assumed on-demand instances)

## Limitations and Future Considerations

### Current Limitations
- Single database (no HA)
- No backup strategy
- No disaster recovery plan
- Development-level security (no TLS, basic secret management)
- No multi-region deployment
- No caching layer

### Future Improvements
- Add Redis caching layer
- Implement database replication
- Add comprehensive monitoring (Prometheus + Grafana)
- Implement centralized logging (ELK stack)
- Add API rate limiting
- Implement OpenAPI/Swagger documentation
- Add API versioning
- Implement request tracing (Jaeger/Zipkin)
- Database backup and recovery procedures
- Multi-environment deployment (dev, staging, prod)
