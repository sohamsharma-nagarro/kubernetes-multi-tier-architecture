# Cloud SQL Deployment Troubleshooting Guide

This guide helps diagnose and fix common issues when deploying to GKE with Cloud SQL.

## Issue Categories

- [Pod and API Issues](#pod-and-api-issues)
- [Cloud SQL Connection Issues](#cloud-sql-connection-issues)
- [Network and VPC Issues](#network-and-vpc-issues)
- [Ingress and Load Balancer Issues](#ingress-and-load-balancer-issues)
- [Performance Issues](#performance-issues)
- [Authentication Issues](#authentication-issues)

---

## Pod and API Issues

### Issue: Pods in CrashLoopBackOff

**Symptoms:**
```bash
$ kubectl get pods -n multi-tier
api-service-xxxxx   0/1     CrashLoopBackOff   5 (10s ago)   2m
```

**Diagnosis:**

1. Check pod logs:
```bash
kubectl logs -n multi-tier deployment/api-service
kubectl logs -n multi-tier deployment/api-service --previous
```

2. Describe pod for more details:
```bash
kubectl describe pod -n multi-tier -l app=api-service
```

3. Check events:
```bash
kubectl get events -n multi-tier --sort-by='.lastTimestamp'
```

**Solutions:**

| Log Message | Solution |
|------------|----------|
| `Connection refused` | Check Cloud SQL IP and connectivity |
| `FATAL: database "..." does not exist` | Create database: `gcloud sql databases create $DB_NAME` |
| `FATAL: role "..." does not exist` | Create user: `gcloud sql users set-password $DB_USER --instance=$INSTANCE_NAME` |
| `Invalid DSN` | Check `DB_HOST`, `DB_PORT`, `DB_NAME` in secrets |
| `OOM Killed` | Increase memory limits in deployment |

### Issue: Pods Pending

**Symptoms:**
```bash
$ kubectl get pods -n multi-tier
api-service-xxxxx   0/1     Pending   0   5m
```

**Causes:**
1. Insufficient node resources
2. Pod scheduling constraints
3. PVC not bound

**Solutions:**

```bash
# Check node capacity
kubectl describe nodes

# Check resource requests
kubectl describe pod -n multi-tier -l app=api-service

# Check for scheduling events
kubectl describe pod -n multi-tier -l app=api-service | grep -A5 Events

# Check HPA didn't scale beyond available resources
kubectl get hpa -n multi-tier -o wide
```

### Issue: High Memory/CPU Usage

**Symptoms:**
```bash
kubectl get pods -n multi-tier --sort-by='{.spec.containers[0].resources.limits.memory}'
```

**Solutions:**

1. **Check connection pooling:**
```bash
# Verify connection limits in app code
# Check Cloud SQL max_connections setting
gcloud sql instances describe $INSTANCE_NAME | grep max_connections
```

2. **Monitor metrics:**
```bash
kubectl top pods -n multi-tier
kubectl top nodes
```

3. **Increase resources:**
```bash
# Edit deployment
kubectl edit deployment api-service -n multi-tier

# Update resources section:
# resources:
#   requests:
#     cpu: 200m
#     memory: 256Mi
#   limits:
#     cpu: 1000m
#     memory: 1024Mi
```

---

## Cloud SQL Connection Issues

### Issue: Pods Cannot Connect to Cloud SQL

**Symptoms:**
```
psycopg2.OperationalError: could not connect to server: No route to host
psycopg2.OperationalError: connection refused
```

**Diagnosis:**

1. **Verify Cloud SQL instance exists and is running:**
```bash
gcloud sql instances describe $INSTANCE_NAME

# Check status - should be RUNNABLE
gcloud sql instances describe $INSTANCE_NAME --format="value(state)"
```

2. **Verify private IP is assigned:**
```bash
gcloud sql instances describe $INSTANCE_NAME \
  --format="value(ipAddresses[0].ipAddress)"

# Should return something like: 10.0.0.2
```

3. **Check Kubernetes secret:**
```bash
kubectl get secret db-credentials -n multi-tier -o yaml

# Verify values match:
# - db-host matches the private IP
# - db-port is 5432
# - db-user and db-password are correct
```

4. **Test connectivity from a pod:**
```bash
kubectl run -it --rm --image=postgres:15-alpine --restart=Never \
  --command -- psql -h $DB_HOST -U $DB_USER -d $DB_NAME << EOF
\l
EOF
```

**Solutions:**

1. **If private IP is missing:**
   - Ensure cluster is VPC-native: `gcloud container clusters describe $CLUSTER --zone=$ZONE | grep -i alias`
   - Instance must have private IP enabled: `gcloud sql instances describe $INSTANCE_NAME | grep -i privateIp`

2. **If using wrong network:**
```bash
# Patch instance to use correct network
gcloud sql instances patch $INSTANCE_NAME \
  --network=projects/${PROJECT_ID}/global/networks/${VPC_NAME}
```

3. **If credentials are wrong:**
```bash
# Reset user password
gcloud sql users set-password $DB_USER \
  --instance=$INSTANCE_NAME \
  --****** 

# Update secret
kubectl create secret generic db-credentials \
  -n multi-tier \
  --from-literal=DB_HOST="$DB_HOST" \
  --from-literal=DB_PORT="5432" \
  --from-literal=DB_NAME="$DB_NAME" \
  --from-literal=DB_USER="$DB_USER" \
  --from-literal=DB_PASSWORD="NEW_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart pods to pick up new secret
kubectl rollout restart deployment/api-service -n multi-tier
```

### Issue: Too Many Connections

**Symptoms:**
```
FATAL: too many connections for role "dbuser"
FATAL: remaining connection slots reserved for non-replication superuser connections
```

**Causes:**
- Connection pool size too large
- Connection leaks in application code
- Previous pod replicas not cleaned up

**Solutions:**

1. **Check current connections:**
```bash
# Connect to Cloud SQL (if you have public IP access)
gcloud cloud-sql-proxy $INSTANCE_NAME &
psql -h localhost -U $DB_USER -d $DB_NAME

# Then run:
SELECT count(*) FROM pg_stat_activity;
SELECT * FROM pg_stat_activity;
```

2. **Increase connection limit:**
```bash
gcloud sql instances patch $INSTANCE_NAME \
  --database-flags=max_connections=200
```

3. **Reduce pool size in app:**
```bash
# Edit api-deployment.yaml
# Add or modify environment variable:
# - name: DB_POOL_SIZE
#   value: "5"
```

4. **Check for zombie connections:**
```bash
# Restart all pods to close stale connections
kubectl rollout restart deployment/api-service -n multi-tier
```

---

## Network and VPC Issues

### Issue: VPC Network Not Found

**Error:**
```
Error: Invalid value for '--network': Invalid network
```

**Solution:**

1. **List available networks:**
```bash
gcloud compute networks list
```

2. **Use the correct network name:**
```bash
# Usually "default" but could be custom
export VPC_NAME="default"

# Create instance with correct network
gcloud sql instances create $INSTANCE_NAME \
  --network=projects/${PROJECT_ID}/global/networks/${VPC_NAME}
```

### Issue: Cluster Not VPC-Native

**Check:**
```bash
gcloud container clusters describe $CLUSTER --zone=$ZONE | grep -i "alias\|Enable"
```

**Solution:**
```bash
# Create new cluster with VPC-native enabled
gcloud container clusters create $CLUSTER \
  --zone=$ZONE \
  --num-nodes=2 \
  --enable-ip-alias \
  --network=$VPC_NAME
```

### Issue: Private Service Connection Misconfigured

**Symptom:**
```
Error: Instance does not have an IP in the private IP range
```

**Solution:**

1. **Verify service connection exists:**
```bash
gcloud services vpc-peerings list \
  --service=servicenetworking.googleapis.com
```

2. **If missing, create it:**
```bash
gcloud services vpc-peerings connect \
  --service=servicenetworking.googleapis.com \
  --ranges=google-managed-services-${VPC_NAME} \
  --network=${VPC_NAME}
```

---

## Ingress and Load Balancer Issues

### Issue: Ingress IP Stuck in Pending

**Symptoms:**
```bash
$ kubectl get ingress -n multi-tier
NAME           CLASS   HOSTS   ADDRESS   PORTS   AGE
api-ingress    gce             <pending> 80      10m
```

**Diagnosis:**

```bash
# Describe ingress for events
kubectl describe ingress -n multi-tier
kubectl get events -n multi-tier --sort-by='.lastTimestamp'
```

**Solutions:**

1. **Wait longer** (GKE ingress provisioning takes 5-15 minutes)

2. **Check service is accessible:**
```bash
kubectl get svc -n multi-tier
kubectl describe svc api-service -n multi-tier
```

3. **Check quota limits:**
```bash
gcloud compute project-info describe --project=$PROJECT_ID | grep -i QUOTA
```

4. **Manually assign static IP:**
```bash
# Reserve static IP
gcloud compute addresses create api-ip --global --project=$PROJECT_ID

# Update ingress to use it
kubectl patch ingress api-ingress -n multi-tier --type=merge \
  -p '{"metadata":{"annotations":{"kubernetes.io/ingress.global-static-ip-name":"api-ip"}}}'
```

### Issue: 502/503 Errors from Ingress

**Symptoms:**
```
HTTP 502 Bad Gateway
HTTP 503 Service Unavailable
```

**Diagnosis:**

```bash
# Check backend health
gcloud compute backend-services list
gcloud compute backend-services get-health api-service-backend

# Check pod logs
kubectl logs -n multi-tier deployment/api-service
```

**Solutions:**

1. **Ensure pods are healthy:**
```bash
# Check readiness probe
kubectl get pods -n multi-tier -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'

# If pods are NotReady, check logs:
kubectl logs -n multi-tier deployment/api-service
```

2. **Check health check endpoint:**
```bash
# Port forward and test
kubectl port-forward -n multi-tier service/api-service 5000:5000
curl -v http://localhost:5000/ready
curl -v http://localhost:5000/health
```

3. **Increase probe timeouts:**
```bash
kubectl edit deployment api-service -n multi-tier

# Update:
# readinessProbe:
#   initialDelaySeconds: 30
#   timeoutSeconds: 10
#   periodSeconds: 5
```

---

## Performance Issues

### Issue: Slow API Responses

**Diagnosis:**

1. **Check API pod metrics:**
```bash
kubectl top pods -n multi-tier
kubectl top nodes
```

2. **Check database query performance:**
```bash
# Connect to Cloud SQL
kubectl run -it --rm --image=postgres:15-alpine --restart=Never \
  --command -- psql -h $DB_HOST -U $DB_USER -d $DB_NAME << EOF
SELECT query, calls, mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;
EOF
```

3. **Check network latency:**
```bash
kubectl exec -it -n multi-tier pod/api-service-xxxxx -- \
  /bin/sh -c 'apt-get update && apt-get install -y iputils-ping && ping -c 4 $DB_HOST'
```

**Solutions:**

1. **Enable query logging:**
```bash
gcloud sql instances patch $INSTANCE_NAME \
  --database-flags=log_min_duration_statement=1000
```

2. **Add database indexes:**
```bash
# Connect and analyze slow queries
kubectl run -it --rm --image=postgres:15-alpine --restart=Never \
  --command -- psql -h $DB_HOST -U $DB_USER -d $DB_NAME << EOF
\d
EXPLAIN ANALYZE SELECT ...;
EOF
```

3. **Scale horizontally:**
```bash
# Increase HPA settings
kubectl edit hpa api-service-hpa -n multi-tier

# Update:
# maxReplicas: 10
# targetAverageUtilization: 60
```

---

## Authentication Issues

### Issue: Access Denied with Credentials

**Symptoms:**
```
FATAL: password authentication failed for user "dbuser"
FATAL: Invalid username/password.
```

**Solutions:**

1. **Verify credentials:**
```bash
echo $DB_USER
echo $DB_PASS
```

2. **Reset password:**
```bash
gcloud sql users set-password $DB_USER \
  --instance=$INSTANCE_NAME \
  --****** 

# Test directly
gcloud cloud-sql-proxy $INSTANCE_NAME &
psql -h localhost -U $DB_USER -d $DB_NAME
```

3. **Update Kubernetes secret:**
```bash
kubectl create secret generic db-credentials \
  -n multi-tier \
  --from-literal=DB_PASSWORD="NEW_SECURE_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart pods
kubectl rollout restart deployment/api-service -n multi-tier
```

### Issue: IAM Permission Denied

**Symptoms:**
```
gcloud error: (google.auth.exceptions.RefreshError) An error occurred
```

**Solution:**

1. **Check IAM permissions:**
```bash
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:*"
```

2. **Grant required roles:**
```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member=serviceAccount:$SERVICE_ACCOUNT \
  --role=roles/cloudsql.client
```

---

## Debugging Commands Cheat Sheet

```bash
# Comprehensive status check
echo "=== Cluster Status ==="
kubectl get nodes
kubectl get namespaces

echo "=== Pod Status ==="
kubectl get pods -n multi-tier
kubectl get deployment -n multi-tier
kubectl describe pod -n multi-tier -l app=api-service

echo "=== Database Status ==="
gcloud sql instances list
gcloud sql instances describe $INSTANCE_NAME

echo "=== Service Status ==="
kubectl get svc -n multi-tier
kubectl get ingress -n multi-tier

echo "=== Logs ==="
kubectl logs -n multi-tier deployment/api-service --tail=50

echo "=== Events ==="
kubectl get events -n multi-tier --sort-by='.lastTimestamp' | head -20
```

## Still Having Issues?

1. **Collect debug information:**
```bash
kubectl get all -n multi-tier -o yaml > debug.yaml
gcloud sql instances describe $INSTANCE_NAME > sql-debug.txt
kubectl logs -n multi-tier deployment/api-service > api-logs.txt
```

2. **Check GCP support documentation:**
   - [GKE Troubleshooting](https://cloud.google.com/kubernetes-engine/docs/troubleshooting)
   - [Cloud SQL Troubleshooting](https://cloud.google.com/sql/docs/postgres/troubleshooting)

3. **Enable debug logging:**
```bash
kubectl set env deployment/api-service -n multi-tier DEBUG=true
kubectl rollout restart deployment/api-service -n multi-tier
```

4. **Contact GCP Support** if issues persist
