#!/bin/bash

################################################################################
# Cloud SQL Deployment Script for GKE
# This script automates the deployment of the multi-tier architecture to GKE
# with Cloud SQL (Private IP) instead of in-cluster PostgreSQL
#
# Prerequisites:
#   - gcloud CLI installed and authenticated
#   - kubectl installed
#   - Appropriate IAM permissions in GCP
#
# Usage:
#   ./scripts/deploy-cloud-sql.sh
#
# Environment variables (set before running):
#   PROJECT_ID, REGION, ZONE, CLUSTER, VPC_NAME, SUBNET
#   INSTANCE_NAME, DB_NAME, DB_USER, DB_PASS
#   IMAGE_TAG, NAMESPACE, SERVICE_ACCOUNT_NAME
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

# Validate environment variables
validate_env_vars() {
    local required_vars=(
        "PROJECT_ID"
        "REGION"
        "ZONE"
        "CLUSTER"
        "VPC_NAME"
        "INSTANCE_NAME"
        "DB_NAME"
        "DB_USER"
        "DB_PASS"
        "NAMESPACE"
        "SERVICE_ACCOUNT_NAME"
    )

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Environment variable '$var' is not set"
            exit 1
        fi
    done

    log_success "All required environment variables are set"
}

# Set default values for optional variables
set_defaults() {
    REGION="${REGION:-us-central1}"
    ZONE="${ZONE:-us-central1-a}"
    CLUSTER="${CLUSTER:-api-cluster}"
    VPC_NAME="${VPC_NAME:-default}"
    SUBNET="${SUBNET:-default}"
    IMAGE_TAG="${IMAGE_TAG:-latest}"
    NAMESPACE="${NAMESPACE:-multi-tier}"
    SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-api-k8s-sa}"
}

# Check gcloud installation
check_gcloud() {
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed"
        exit 1
    fi
    log_success "gcloud CLI found"
}

# Check kubectl installation
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi
    log_success "kubectl found"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    gcloud services enable \
        container.googleapis.com \
        sqladmin.googleapis.com \
        artifactregistry.googleapis.com \
        cloudbuild.googleapis.com \
        iam.googleapis.com \
        --project="$PROJECT_ID"
    log_success "APIs enabled"
}

# Create GKE cluster
create_gke_cluster() {
    log_info "Checking if GKE cluster exists..."
    
    if gcloud container clusters describe "$CLUSTER" \
        --zone "$ZONE" \
        --project="$PROJECT_ID" &>/dev/null; then
        log_warning "Cluster '$CLUSTER' already exists"
    else
        log_info "Creating VPC-native GKE cluster..."
        gcloud container clusters create "$CLUSTER" \
            --zone "$ZONE" \
            --num-nodes=2 \
            --enable-ip-alias \
            --network="$VPC_NAME" \
            --subnetwork="$SUBNET" \
            --machine-type=n1-standard-2 \
            --enable-autoscaling \
            --min-nodes=2 \
            --max-nodes=5 \
            --project="$PROJECT_ID"
        log_success "GKE cluster created"
    fi

    log_info "Getting cluster credentials..."
    gcloud container clusters get-credentials "$CLUSTER" \
        --zone "$ZONE" \
        --project="$PROJECT_ID"
    log_success "Cluster credentials obtained"
}

# Create Cloud SQL instance
create_cloud_sql() {
    log_info "Checking if Cloud SQL instance exists..."
    
    if gcloud sql instances describe "$INSTANCE_NAME" \
        --project="$PROJECT_ID" &>/dev/null; then
        log_warning "Cloud SQL instance '$INSTANCE_NAME' already exists"
    else
        log_info "Creating Cloud SQL instance with Private IP..."
        gcloud sql instances create "$INSTANCE_NAME" \
            --database-version=POSTGRES_15 \
            --region="$REGION" \
            --network="projects/${PROJECT_ID}/global/networks/${VPC_NAME}" \
            --no-assign-ip \
            --tier=db-f1-micro \
            --project="$PROJECT_ID"
        log_success "Cloud SQL instance created"
    fi

    # Wait for instance to be ready
    log_info "Waiting for Cloud SQL instance to be ready (this may take a few minutes)..."
    while true; do
        status=$(gcloud sql instances describe "$INSTANCE_NAME" \
            --format="value(state)" \
            --project="$PROJECT_ID" 2>/dev/null || echo "")
        if [[ "$status" == "RUNNABLE" ]]; then
            log_success "Cloud SQL instance is ready"
            break
        fi
        echo -n "."
        sleep 10
    done
}

# Create database and user
setup_database() {
    log_info "Creating database..."
    gcloud sql databases create "$DB_NAME" \
        --instance="$INSTANCE_NAME" \
        --project="$PROJECT_ID" || log_warning "Database may already exist"

    log_info "Setting database user password..."
    gcloud sql users set-password "$DB_USER" \
        --instance="$INSTANCE_NAME" \
        --****** \
        --project="$PROJECT_ID" || true

    log_success "Database setup complete"
}

# Get Cloud SQL private IP
get_sql_private_ip() {
    log_info "Retrieving Cloud SQL private IP address..."
    
    DB_HOST=$(gcloud sql instances describe "$INSTANCE_NAME" \
        --format="value(ipAddresses[0].ipAddress)" \
        --project="$PROJECT_ID")
    
    if [[ -z "$DB_HOST" ]]; then
        log_error "Failed to retrieve Cloud SQL private IP"
        exit 1
    fi
    
    log_success "Cloud SQL Private IP: $DB_HOST"
}

# Create Cloud SQL Proxy service account (optional but recommended)
setup_service_account() {
    log_info "Setting up Kubernetes service account..."
    
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl create serviceaccount "$SERVICE_ACCOUNT_NAME" \
        -n "$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Service account created"
}

# Create Kubernetes secrets for database
create_k8s_secrets() {
    log_info "Creating Kubernetes secrets..."
    
    kubectl create secret generic db-credentials \
        -n "$NAMESPACE" \
        --from-literal=DB_HOST="$DB_HOST" \
        --from-literal=DB_PORT="5432" \
        --from-literal=DB_NAME="$DB_NAME" \
        --from-literal=DB_USER="$DB_USER" \
        --from-literal=DB_PASSWORD="$DB_PASS" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Kubernetes secrets created"
}

# Update ConfigMap for Cloud SQL
update_configmap() {
    log_info "Creating ConfigMap for Cloud SQL..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: db-config
  namespace: $NAMESPACE
data:
  DB_HOST: "$DB_HOST"
  DB_PORT: "5432"
  DB_NAME: "$DB_NAME"
EOF
    
    log_success "ConfigMap created"
}

# Deploy API service
deploy_api_service() {
    log_info "Deploying API service..."
    
    # Check if k8s-cloud-sql directory exists
    if [[ ! -d "k8s-cloud-sql" ]]; then
        log_error "k8s-cloud-sql directory not found"
        log_info "Using standard k8s manifests instead"
        
        # Update image if IMAGE_TAG is not 'latest'
        if [[ "$IMAGE_TAG" != "latest" ]]; then
            sed -i.bak "s|sohamsharma/py-api-service:latest|sohamsharma/py-api-service:${IMAGE_TAG}|g" k8s/api-deployment.yaml
            log_info "Updated image tag to $IMAGE_TAG"
        fi
        
        kubectl apply -f k8s/namespace.yaml
        kubectl apply -f k8s/configmap.yaml
        kubectl apply -f k8s/secrets.yaml
        kubectl apply -f k8s/api-deployment.yaml
        kubectl apply -f k8s/api-service.yaml
        kubectl apply -f k8s/api-hpa.yaml
        kubectl apply -f k8s/ingress.yaml
    else
        kubectl apply -f k8s-cloud-sql/namespace.yaml
        kubectl apply -f k8s-cloud-sql/configmap.yaml
        kubectl apply -f k8s-cloud-sql/secrets.yaml
        kubectl apply -f k8s-cloud-sql/api-deployment.yaml
        kubectl apply -f k8s-cloud-sql/api-service.yaml
        kubectl apply -f k8s-cloud-sql/api-hpa.yaml
        kubectl apply -f k8s-cloud-sql/ingress.yaml
    fi
    
    log_success "API service deployed"
}

# Wait for API to be ready
wait_for_api() {
    log_info "Waiting for API service to be ready..."
    kubectl wait --for=condition=ready pod \
        -l app=api-service \
        -n "$NAMESPACE" \
        --timeout=300s || log_warning "API service readiness check timed out"
    
    log_success "API service is ready"
}

# Get ingress details
show_ingress_info() {
    log_info "Fetching Ingress details..."
    sleep 5
    
    INGRESS_IP=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    if [[ -n "$INGRESS_IP" ]]; then
        log_success "Ingress IP Address: $INGRESS_IP"
        log_info "API will be available at: http://$INGRESS_IP/api/records"
    else
        log_warning "Ingress IP is still pending. Check status with:"
        log_info "kubectl get ingress -n $NAMESPACE"
    fi
}

# Show deployment summary
show_summary() {
    cat <<EOF

${GREEN}════════════════════════════════════════════════════════════════${NC}
${GREEN}         CLOUD SQL DEPLOYMENT COMPLETE${NC}
${GREEN}════════════════════════════════════════════════════════════════${NC}

${BLUE}Deployment Details:${NC}
  Project ID:         $PROJECT_ID
  GKE Cluster:        $CLUSTER
  Region:             $REGION
  Zone:               $ZONE
  Namespace:          $NAMESPACE
  
${BLUE}Cloud SQL Details:${NC}
  Instance Name:      $INSTANCE_NAME
  Database:           $DB_NAME
  Private IP:         $DB_HOST
  Region:             $REGION

${BLUE}Monitoring Commands:${NC}
  View all resources:
    kubectl get all -n $NAMESPACE
  
  View API logs:
    kubectl logs -n $NAMESPACE deployment/api-service
  
  Monitor autoscaling:
    kubectl get hpa -n $NAMESPACE -w
  
  Port forward to API:
    kubectl port-forward -n $NAMESPACE service/api-service 5000:5000

${BLUE}Useful Links:${NC}
  Cloud SQL Instance:
    https://console.cloud.google.com/sql/instances/$INSTANCE_NAME?project=$PROJECT_ID
  
  GKE Cluster:
    https://console.cloud.google.com/kubernetes/clusters/details/$ZONE/$CLUSTER?project=$PROJECT_ID

${GREEN}════════════════════════════════════════════════════════════════${NC}

EOF
}

# Main execution
main() {
    echo ""
    log_info "Starting Cloud SQL Deployment for GKE"
    echo ""

    set_defaults
    validate_env_vars
    check_gcloud
    check_kubectl
    
    enable_apis
    create_gke_cluster
    create_cloud_sql
    setup_database
    get_sql_private_ip
    setup_service_account
    create_k8s_secrets
    update_configmap
    deploy_api_service
    wait_for_api
    show_ingress_info
    show_summary
}

# Run main function
main "$@"
