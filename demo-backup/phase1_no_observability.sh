#!/usr/bin/env bash
# =============================================================================
# DEMO PHASE 1 — The broken system, no observability
#
# What happens:
#   - INTRODUCE_LATENCY_BUG=true  → processor calls external validation API
#   - ENABLE_OBSERVABILITY=false  → no ADOT, no X-Ray, no traces
#   - Send 20 requests → watch p99 climb silently with no visibility
#
# Talking point:
#   "The system looks healthy. No errors. No alerts. But p99 is 8 seconds."
# =============================================================================
set -euo pipefail

API="https://b10v2dz7zd.execute-api.us-east-2.amazonaws.com"
REGION="us-east-2"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  PHASE 1: Silent latency — no observability"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Step 1: Deploy with latency bug ON, observability OFF ─────────────────────
echo "▶ Deploying: latency bug=ON, observability=OFF..."
cd "$(dirname "$0")/../terraform/envs/demo"
terraform apply -auto-approve \
  -var="introduce_latency_bug=true" \
  -var="enable_observability=false" \
  -compact-warnings -no-color 2>&1 | grep -E "Apply complete|module\.|Error"

# Force ECS redeploy with new env vars
echo "▶ Redeploying ECS service..."
REVISION=$(aws ecs describe-task-definition \
  --task-definition obs-talk-demo-processor \
  --region "$REGION" \
  --query 'taskDefinition.revision' --output text)

aws ecs update-service \
  --cluster obs-talk-demo-cluster \
  --service obs-talk-demo-processor \
  --force-new-deployment \
  --region "$REGION" --no-cli-pager > /dev/null

echo "▶ Waiting for service to stabilize..."
aws ecs wait services-stable \
  --cluster obs-talk-demo-cluster \
  --services obs-talk-demo-processor \
  --region "$REGION"
echo "   ✓ ECS service stable"

cd "$(dirname "$0")"

# ── Step 2: Send load ──────────────────────────────────────────────────────────
echo ""
echo "▶ Sending 20 requests (expect ~2s+ each due to latency bug)..."
echo ""

PASS=0; FAIL=0; TOTAL_MS=0

for i in $(seq 1 20); do
  START=$(date +%s%3N)
  RESP=$(curl -s -o /tmp/resp.json -w "%{http_code}" \
    -X POST "$API/ingest" \
    -H "Content-Type: application/json" \
    -d "{\"source\":\"demo-phase1\",\"event_type\":\"data.ingested\",\"payload\":{\"seq\":$i}}")
  END=$(date +%s%3N)
  MS=$((END - START))
  TOTAL_MS=$((TOTAL_MS + MS))

  if [ "$RESP" = "202" ]; then
    RECORD_ID=$(cat /tmp/resp.json | python3 -c "import json,sys; print(json.load(sys.stdin).get('record_id','?'))")
    printf "  [%02d] ✓ %dms  %s\n" "$i" "$MS" "$RECORD_ID"
    PASS=$((PASS + 1))
  else
    printf "  [%02d] ✗ HTTP %s\n" "$i" "$RESP"
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: $PASS ok / $FAIL failed"
AVG=$((TOTAL_MS / 20))
echo "  Avg latency: ${AVG}ms"
echo ""
echo "  ⚠️  System looks healthy — no errors, no alerts."
echo "     But check the processor logs:"
echo "     aws logs tail /ecs/obs-talk-demo/processor --region $REGION --since 3m"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next: run phase2_with_observability.sh"
