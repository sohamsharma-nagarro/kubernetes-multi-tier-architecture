#!/bin/bash

NAMESPACE="multi-tier"
SERVICE_NAME="api-service"

echo "🧪 Testing API Service..."
echo ""

# Get service IP or use port-forward
echo "⏳ Getting service information..."
SERVICE_IP=$(kubectl get service $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [ -z "$SERVICE_IP" ]; then
    echo "Using port-forward (LoadBalancer IP not available yet)..."
    kubectl port-forward -n $NAMESPACE svc/$SERVICE_NAME 5000:80 &
    PF_PID=$!
    sleep 3
    BASE_URL="http://localhost:5000"
else
    BASE_URL="http://$SERVICE_IP"
fi

echo "Base URL: $BASE_URL"
echo ""

# Test health endpoint
echo "1️⃣  Testing /health endpoint..."
if curl -s -X GET "$BASE_URL/health" | jq . 2>/dev/null; then
    echo "✅ Health check passed"
else
    echo "❌ Health check failed"
fi
echo ""

# Test ready endpoint
echo "2️⃣  Testing /ready endpoint..."
if curl -s -X GET "$BASE_URL/ready" | jq . 2>/dev/null; then
    echo "✅ Ready check passed"
else
    echo "❌ Ready check failed"
fi
echo ""

# Test get all records
echo "3️⃣  Testing GET /api/records..."
if curl -s -X GET "$BASE_URL/api/records" | jq . 2>/dev/null; then
    echo "✅ Get all records passed"
else
    echo "❌ Get all records failed"
fi
echo ""

# Test get specific record
echo "4️⃣  Testing GET /api/records/1..."
if curl -s -X GET "$BASE_URL/api/records/1" | jq . 2>/dev/null; then
    echo "✅ Get specific record passed"
else
    echo "❌ Get specific record failed"
fi
echo ""

# Test health info
echo "5️⃣  Testing GET /api/health-info..."
if curl -s -X GET "$BASE_URL/api/health-info" | jq . 2>/dev/null; then
    echo "✅ Health info passed"
else
    echo "❌ Health info failed"
fi
echo ""

# Cleanup port-forward if used
if [ ! -z "$PF_PID" ]; then
    kill $PF_PID 2>/dev/null || true
fi

echo "✅ API testing complete!"
