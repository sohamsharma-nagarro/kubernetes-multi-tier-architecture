#!/bin/bash

# Multi-Tier Kubernetes Architecture Verification Script
# This script validates the entire deployment and tests all requirements

set -e

NAMESPACE="multi-tier"
API_SERVICE="api-service"
DB_SERVICE="postgres-db"
COLORS_GREEN='\033[0;32m'
COLORS_RED='\033[0;31m'
COLORS_YELLOW='\033[1;33m'
COLORS_BLUE='\033[0;34m'
COLORS_NC='\033[0m'

echo -e "${COLORS_BLUE}🔍 Multi-Tier Kubernetes Architecture Verification${COLORS_NC}"
echo ""

# Counter for checks
PASSED=0
FAILED=0
WARNINGS=0

# Function to print success
success() {
    echo -e "${COLORS_GREEN}✅ $1${COLORS_NC}"
    ((PASSED++))
}

# Function to print failure
failure() {
    echo -e "${COLORS_RED}❌ $1${COLORS_NC}"
    ((FAILED++))
}

# Function to print warning
warning() {
    echo -e "${COLORS_YELLOW}⚠️  $1${COLORS_NC}"
    ((WARNINGS++))
}

# Function to print section header
section() {
    echo ""
    echo -e "${COLORS_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLORS_NC}"
    echo -e "${COLORS_BLUE}$1${COLORS_NC}"
    echo -e "${COLORS_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLORS_NC}"
}

# Verify Kubernetes cluster access
section "1. Kubernetes Cluster Access"
if kubectl cluster-info &>/dev/null; then
    success "Kubernetes cluster is accessible"
else
    failure "Kubernetes cluster is not accessible"
    exit 1
fi

# Check namespace exists
if kubectl get namespace $NAMESPACE &>/dev/null; then
    success "Namespace '$NAMESPACE' exists"
else
    failure "Namespace '$NAMESPACE' does not exist"
fi

# Verify Namespace Resources
section "2. Namespace Resources"
RESOURCE_COUNT=$(kubectl get all -n $NAMESPACE --no-headers 2>/dev/null | wc -l)
if [ $RESOURCE_COUNT -gt 0 ]; then
    success "Namespace contains $RESOURCE_COUNT resources"
else
    failure "Namespace contains no resources"
fi

# Verify ConfigMaps
section "3. ConfigMap Verification"
if kubectl get configmap db-config -n $NAMESPACE &>/dev/null; then
    success "ConfigMap 'db-config' exists"
    DB_HOST=$(kubectl get configmap db-config -n $NAMESPACE -o jsonpath='{.data.DB_HOST}')
    DB_PORT=$(kubectl get configmap db-config -n $NAMESPACE -o jsonpath='{.data.DB_PORT}')
    DB_NAME=$(kubectl get configmap db-config -n $NAMESPACE -o jsonpath='{.data.DB_NAME}')
    echo "  - DB_HOST: $DB_HOST"
    echo "  - DB_PORT: $DB_PORT"
    echo "  - DB_NAME: $DB_NAME"
else
    failure "ConfigMap 'db-config' not found"
fi

if kubectl get configmap init-script -n $NAMESPACE &>/dev/null; then
    success "ConfigMap 'init-script' exists"
else
    failure "ConfigMap 'init-script' not found"
fi

# Verify Secrets
section "4. Secrets Verification"
if kubectl get secret db-credentials -n $NAMESPACE &>/dev/null; then
    success "Secret 'db-credentials' exists"
else
    failure "Secret 'db-credentials' not found"
fi

# Verify PVC
section "5. Persistent Volume Claims"
if kubectl get pvc postgres-pvc -n $NAMESPACE &>/dev/null; then
    success "PVC 'postgres-pvc' exists"
    PVC_SIZE=$(kubectl get pvc postgres-pvc -n $NAMESPACE -o jsonpath='{.spec.resources.requests.storage}')
    PVC_STATUS=$(kubectl get pvc postgres-pvc -n $NAMESPACE -o jsonpath='{.status.phase}')
    echo "  - Size: $PVC_SIZE"
    echo "  - Status: $PVC_STATUS"
    
    if [ "$PVC_STATUS" == "Bound" ]; then
        success "PVC is bound to a PersistentVolume"
    else
        warning "PVC status is $PVC_STATUS (expected Bound)"
    fi
else
    failure "PVC 'postgres-pvc' not found"
fi

# Verify Deployments
section "6. Deployment Verification"

# Check API Deployment
if kubectl get deployment $API_SERVICE -n $NAMESPACE &>/dev/null; then
    success "Deployment '$API_SERVICE' exists"
    
    REPLICAS=$(kubectl get deployment $API_SERVICE -n $NAMESPACE -o jsonpath='{.spec.replicas}')
    READY=$(kubectl get deployment $API_SERVICE -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
    echo "  - Desired replicas: $REPLICAS"
    echo "  - Ready replicas: $READY"
    
    if [ "$REPLICAS" == "$READY" ]; then
        success "All API replicas are ready ($READY/$REPLICAS)"
    else
        warning "Not all API replicas are ready ($READY/$REPLICAS)"
    fi
else
    failure "Deployment '$API_SERVICE' not found"
fi

# Check Database Deployment
if kubectl get deployment $DB_SERVICE -n $NAMESPACE &>/dev/null; then
    success "Deployment '$DB_SERVICE' exists"
    
    DB_REPLICAS=$(kubectl get deployment $DB_SERVICE -n $NAMESPACE -o jsonpath='{.spec.replicas}')
    DB_READY=$(kubectl get deployment $DB_SERVICE -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
    echo "  - Desired replicas: $DB_REPLICAS"
    echo "  - Ready replicas: $DB_READY"
    
    if [ "$DB_REPLICAS" == "$DB_READY" ]; then
        success "All Database replicas are ready ($DB_READY/$DB_REPLICAS)"
    else
        warning "Not all Database replicas are ready ($DB_READY/$DB_REPLICAS)"
    fi
else
    failure "Deployment '$DB_SERVICE' not found"
fi

# Verify Services
section "7. Services Verification"

# Check API Service
if kubectl get service $API_SERVICE -n $NAMESPACE &>/dev/null; then
    success "Service '$API_SERVICE' exists"
    SERVICE_TYPE=$(kubectl get service $API_SERVICE -n $NAMESPACE -o jsonpath='{.spec.type}')
    echo "  - Type: $SERVICE_TYPE"
    
    if [ "$SERVICE_TYPE" == "LoadBalancer" ]; then
        success "API service type is LoadBalancer"
        EXTERNAL_IP=$(kubectl get service $API_SERVICE -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
        echo "  - External IP: $EXTERNAL_IP"
    fi
else
    failure "Service '$API_SERVICE' not found"
fi

# Check Database Service
if kubectl get service $DB_SERVICE -n $NAMESPACE &>/dev/null; then
    success "Service '$DB_SERVICE' exists"
    DB_SERVICE_TYPE=$(kubectl get service $DB_SERVICE -n $NAMESPACE -o jsonpath='{.spec.type}')
    echo "  - Type: $DB_SERVICE_TYPE"
    
    if [ "$DB_SERVICE_TYPE" == "ClusterIP" ]; then
        success "Database service type is ClusterIP (internal only)"
    else
        warning "Database service type is $DB_SERVICE_TYPE (expected ClusterIP)"
    fi
else
    failure "Service '$DB_SERVICE' not found"
fi

# Verify Ingress
section "8. Ingress Verification"
if kubectl get ingress -n $NAMESPACE &>/dev/null; then
    INGRESS_COUNT=$(kubectl get ingress -n $NAMESPACE --no-headers | wc -l)
    success "Found $INGRESS_COUNT Ingress resource(s)"
else
    warning "No Ingress resources found"
fi

# Verify HPA
section "9. Horizontal Pod Autoscaler (HPA)"
if kubectl get hpa -n $NAMESPACE &>/dev/null; then
    HPA_COUNT=$(kubectl get hpa -n $NAMESPACE --no-headers | wc -l)
    success "Found $HPA_COUNT HPA resource(s)"
    
    HPA_NAME=$(kubectl get hpa -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ ! -z "$HPA_NAME" ]; then
        MIN_REPLICAS=$(kubectl get hpa "$HPA_NAME" -n $NAMESPACE -o jsonpath='{.spec.minReplicas}')
        MAX_REPLICAS=$(kubectl get hpa "$HPA_NAME" -n $NAMESPACE -o jsonpath='{.spec.maxReplicas}')
        echo "  - HPA: $HPA_NAME"
        echo "  - Min Replicas: $MIN_REPLICAS"
        echo "  - Max Replicas: $MAX_REPLICAS"
    fi
else
    failure "No HPA resources found"
fi

# Verify Pod Status
section "10. Pod Health Status"
API_PODS=$(kubectl get pods -n $NAMESPACE -l app=$API_SERVICE -o jsonpath='{.items[*].metadata.name}')
for POD in $API_PODS; do
    STATUS=$(kubectl get pod $POD -n $NAMESPACE -o jsonpath='{.status.phase}')
    if [ "$STATUS" == "Running" ]; then
        success "API Pod '$POD' is Running"
    else
        warning "API Pod '$POD' status is $STATUS"
    fi
done

DB_POD=$(kubectl get pods -n $NAMESPACE -l app=$DB_SERVICE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ ! -z "$DB_POD" ]; then
    DB_STATUS=$(kubectl get pod $DB_POD -n $NAMESPACE -o jsonpath='{.status.phase}')
    if [ "$DB_STATUS" == "Running" ]; then
        success "Database Pod '$DB_POD' is Running"
    else
        warning "Database Pod '$DB_POD' status is $DB_STATUS"
    fi
fi

# Verify Resource Limits
section "11. Resource Requests and Limits"
API_CONTAINER=$(kubectl get deployment $API_SERVICE -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0]}' 2>/dev/null)
if [ ! -z "$API_CONTAINER" ]; then
    CPU_REQUEST=$(echo "$API_CONTAINER" | grep -o '"cpu":"[^"]*' | cut -d'"' -f4)
    MEMORY_REQUEST=$(echo "$API_CONTAINER" | grep -o '"memory":"[^"]*' | cut -d'"' -f4)
    
    if [ ! -z "$CPU_REQUEST" ] && [ ! -z "$MEMORY_REQUEST" ]; then
        success "API pod has resource requests defined"
        echo "  - CPU Request: $CPU_REQUEST"
        echo "  - Memory Request: $MEMORY_REQUEST"
    else
        warning "API pod resource requests not fully defined"
    fi
fi

# Test API Connectivity
section "12. API Endpoint Testing"
if [ ! -z "$DB_POD" ] && [ "$DB_STATUS" == "Running" ]; then
    # Port-forward to test API
    kubectl port-forward -n $NAMESPACE service/$API_SERVICE 8888:80 &
    PF_PID=$!
    sleep 2
    
    # Test /health endpoint
    if curl -s http://localhost:8888/health &>/dev/null; then
        success "API /health endpoint is responding"
    else
        warning "API /health endpoint not responding (database might not be ready)"
    fi
    
    # Test /api/records endpoint
    if curl -s http://localhost:8888/api/records &>/dev/null; then
        success "API /api/records endpoint is responding"
        RECORD_COUNT=$(curl -s http://localhost:8888/api/records | grep -o '"count":[0-9]*' | cut -d':' -f2)
        if [ ! -z "$RECORD_COUNT" ]; then
            echo "  - Records in database: $RECORD_COUNT"
            if [ "$RECORD_COUNT" -ge 5 ]; then
                success "Database has sufficient records ($RECORD_COUNT >= 5)"
            else
                failure "Database has insufficient records ($RECORD_COUNT < 5)"
            fi
        fi
    else
        warning "API /api/records endpoint not responding"
    fi
    
    # Clean up port-forward
    kill $PF_PID 2>/dev/null || true
else
    warning "Database pod not ready, skipping API connectivity tests"
fi

# Verify Data Persistence
section "13. Data Persistence Verification"
if [ ! -z "$DB_POD" ]; then
    # Check if PVC has data
    VOLUME_SIZE=$(kubectl get pvc postgres-pvc -n $NAMESPACE -o jsonpath='{.status.capacity.storage}' 2>/dev/null)
    if [ ! -z "$VOLUME_SIZE" ]; then
        success "PVC has allocated storage: $VOLUME_SIZE"
    fi
    
    # Verify mount point
    MOUNT_PATH=$(kubectl get deployment $DB_SERVICE -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[0].mountPath}' 2>/dev/null)
    if [ ! -z "$MOUNT_PATH" ]; then
        success "Database volume mounted at: $MOUNT_PATH"
    fi
fi

# Verify Rolling Update Support
section "14. Rolling Update Configuration"
STRATEGY=$(kubectl get deployment $API_SERVICE -n $NAMESPACE -o jsonpath='{.spec.strategy.type}' 2>/dev/null)
if [ "$STRATEGY" == "RollingUpdate" ]; then
    success "API deployment uses RollingUpdate strategy"
    MAX_SURGE=$(kubectl get deployment $API_SERVICE -n $NAMESPACE -o jsonpath='{.spec.strategy.rollingUpdate.maxSurge}' 2>/dev/null)
    MAX_UNAVAILABLE=$(kubectl get deployment $API_SERVICE -n $NAMESPACE -o jsonpath='{.spec.strategy.rollingUpdate.maxUnavailable}' 2>/dev/null)
    echo "  - Max Surge: $MAX_SURGE"
    echo "  - Max Unavailable: $MAX_UNAVAILABLE"
else
    warning "API deployment strategy is $STRATEGY (expected RollingUpdate)"
fi

# Verify Probes
section "15. Health Probes Configuration"
LIVENESS_PROBE=$(kubectl get deployment $API_SERVICE -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}' 2>/dev/null)
READINESS_PROBE=$(kubectl get deployment $API_SERVICE -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}' 2>/dev/null)

if [ ! -z "$LIVENESS_PROBE" ]; then
    success "API deployment has liveness probe configured"
else
    failure "API deployment missing liveness probe"
fi

if [ ! -z "$READINESS_PROBE" ]; then
    success "API deployment has readiness probe configured"
else
    failure "API deployment missing readiness probe"
fi

DB_LIVENESS=$(kubectl get deployment $DB_SERVICE -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}' 2>/dev/null)
if [ ! -z "$DB_LIVENESS" ]; then
    success "Database deployment has liveness probe configured"
else
    failure "Database deployment missing liveness probe"
fi

# Summary
section "📊 Verification Summary"
echo ""
echo -e "Checks Passed:  ${COLORS_GREEN}$PASSED${COLORS_NC}"
echo -e "Checks Failed:  ${COLORS_RED}$FAILED${COLORS_NC}"
echo -e "Warnings:       ${COLORS_YELLOW}$WARNINGS${COLORS_NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${COLORS_GREEN}🎉 All critical checks passed!${COLORS_NC}"
    exit 0
else
    echo -e "${COLORS_RED}❌ Some critical checks failed. Please review above.${COLORS_NC}"
    exit 1
fi
