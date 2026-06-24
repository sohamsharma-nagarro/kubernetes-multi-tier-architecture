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

PASS=0
FAIL=0

run_test() {
    local name="$1"
    local result="$2"
    if [ "$result" = "0" ]; then
        echo "✅ $name passed"
        PASS=$((PASS + 1))
    else
        echo "❌ $name failed"
        FAIL=$((FAIL + 1))
    fi
}

# Test health endpoint
echo "1️⃣  Testing GET /health..."
curl -sf -X GET "$BASE_URL/health" | jq . 2>/dev/null
run_test "GET /health" $?
echo ""

# Test ready endpoint
echo "2️⃣  Testing GET /ready..."
curl -sf -X GET "$BASE_URL/ready" | jq . 2>/dev/null
run_test "GET /ready" $?
echo ""

# Test get all records
echo "3️⃣  Testing GET /api/records..."
curl -sf -X GET "$BASE_URL/api/records" | jq . 2>/dev/null
run_test "GET /api/records" $?
echo ""

# Test get specific record
echo "4️⃣  Testing GET /api/records/1..."
curl -sf -X GET "$BASE_URL/api/records/1" | jq . 2>/dev/null
run_test "GET /api/records/1" $?
echo ""

# Test create record
echo "5️⃣  Testing POST /api/records..."
CREATE_RESPONSE=$(curl -sf -X POST "$BASE_URL/api/records" \
  -H "Content-Type: application/json" \
  -d '{"name":"Test User","email":"testuser@company.com","department":"QA","salary":75000,"hire_date":"2024-01-01"}')
echo "$CREATE_RESPONSE" | jq . 2>/dev/null
if [ $? -eq 0 ]; then
    NEW_ID=$(echo "$CREATE_RESPONSE" | jq -r '.data.id')
    run_test "POST /api/records" 0
else
    run_test "POST /api/records" 1
fi
echo ""

# Test update record
if [ ! -z "$NEW_ID" ] && [ "$NEW_ID" != "null" ]; then
    echo "6️⃣  Testing PUT /api/records/$NEW_ID..."
    curl -sf -X PUT "$BASE_URL/api/records/$NEW_ID" \
      -H "Content-Type: application/json" \
      -d '{"salary":80000}' | jq . 2>/dev/null
    run_test "PUT /api/records/$NEW_ID" $?
    echo ""

    # Test delete record
    echo "7️⃣  Testing DELETE /api/records/$NEW_ID..."
    curl -sf -X DELETE "$BASE_URL/api/records/$NEW_ID" | jq . 2>/dev/null
    run_test "DELETE /api/records/$NEW_ID" $?
    echo ""
fi

# Test health info
echo "8️⃣  Testing GET /api/health-info..."
curl -sf -X GET "$BASE_URL/api/health-info" | jq . 2>/dev/null
run_test "GET /api/health-info" $?
echo ""

# Cleanup port-forward if used
if [ ! -z "$PF_PID" ]; then
    kill $PF_PID 2>/dev/null || true
fi

echo "──────────────────────────────"
echo "Results: ✅ $PASS passed  ❌ $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "✅ All API tests passed!"
    exit 0
else
    echo "❌ Some tests failed!"
    exit 1
fi
