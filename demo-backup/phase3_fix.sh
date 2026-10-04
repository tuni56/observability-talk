#!/usr/bin/env bash
# =============================================================================
# DEMO PHASE 3 — The fix: disable the latency bug, prove it with data
#
# What happens:
#   - INTRODUCE_LATENCY_BUG=false → external_validation call removed
#   - ENABLE_OBSERVABILITY=true   → ADOT still running
#   - Send 20 requests → p99 drops from ~8s to ~400ms
#   - Show before/after in CloudWatch dashboard
#
# Talking point:
#   "One config change. p99: 8400ms → 380ms."
#   "And we have the traces to prove the fix worked."
# =============================================================================
set -euo pipefail

API="https://b10v2dz7zd.execute-api.us-east-2.amazonaws.com"
REGION="us-east-2"
DASHBOARD_URL="https://${REGION}.console.aws.amazon.com/cloudwatch/home?region=${REGION}#dashboards:name=obs-talk-demo-observability"
XRAY_URL="https://${REGION}.console.aws.amazon.com/xray/home?region=${REGION}#/traces"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  PHASE 3: The fix — disable latency bug"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Step 1: Apply the fix ──────────────────────────────────────────────────────
echo "▶ Deploying fix: latency bug=OFF, observability=ON..."
cd "$(dirname "$0")/../terraform/envs/demo"
terraform apply -auto-approve \
  -var="introduce_latency_bug=false" \
  -var="enable_observability=true" \
  -compact-warnings -no-color 2>&1 | grep -E "Apply complete|module\.|Error"

echo "▶ Redeploying ECS service..."
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
echo "   ✓ Fixed version running"

cd "$(dirname "$0")"

# ── Step 2: Send load ──────────────────────────────────────────────────────────
echo ""
echo "▶ Sending 20 requests (should be fast now)..."
echo ""

PASS=0; FAIL=0; TOTAL_MS=0; MAX_MS=0; MIN_MS=99999

for i in $(seq 1 20); do
  START=$(date +%s%3N)
  RESP=$(curl -s -o /tmp/resp.json -w "%{http_code}" \
    -X POST "$API/ingest" \
    -H "Content-Type: application/json" \
    -d "{\"source\":\"demo-phase3\",\"event_type\":\"data.ingested\",\"payload\":{\"seq\":$i}}")
  END=$(date +%s%3N)
  MS=$((END - START))
  TOTAL_MS=$((TOTAL_MS + MS))
  [ $MS -gt $MAX_MS ] && MAX_MS=$MS
  [ $MS -lt $MIN_MS ] && MIN_MS=$MS

  if [ "$RESP" = "202" ]; then
    RECORD_ID=$(cat /tmp/resp.json | python3 -c "import json,sys; print(json.load(sys.stdin).get('record_id','?'))")
    printf "  [%02d] ✓ %dms  %s\n" "$i" "$MS" "$RECORD_ID"
    PASS=$((PASS + 1))
  else
    printf "  [%02d] ✗ HTTP %s\n" "$i" "$RESP"
    FAIL=$((FAIL + 1))
  fi
done

AVG=$((TOTAL_MS / 20))

# ── Step 3: Show evidence ──────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: $PASS ok / $FAIL failed"
echo ""
echo "  Latency (API Gateway round-trip):"
echo "    min: ${MIN_MS}ms   avg: ${AVG}ms   max: ${MAX_MS}ms"
echo ""
echo "  📊 CloudWatch Dashboard (before vs after visible):"
echo "     $DASHBOARD_URL"
echo ""
echo "  🔍 X-Ray Traces (no more fat external_validation span):"
echo "     $XRAY_URL"
echo ""

# Show processor duration from logs
echo "  Processor duration from structured logs:"
aws logs filter-log-events \
  --log-group-name /ecs/obs-talk-demo/processor \
  --region "$REGION" \
  --start-time $(($(date +%s%3N) - 120000)) \
  --filter-pattern "{ $.message = \"Record processed\" }" \
  --query 'events[*].message' \
  --output text 2>/dev/null | \
  python3 -c "
import sys, json
durations = []
for line in sys.stdin:
    try:
        d = json.loads(line.strip())
        durations.append(d.get('duration_ms', 0))
    except: pass
if durations:
    durations.sort()
    print(f'    count={len(durations)}  p50={durations[len(durations)//2]}ms  p99={durations[int(len(durations)*0.99)]}ms  max={max(durations)}ms')
else:
    print('    (no data yet — wait 10s and check CloudWatch Logs)')
"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Demo complete."
echo "  'Governance is a contract, not a checkpoint.'"
echo ""
