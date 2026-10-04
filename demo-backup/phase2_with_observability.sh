#!/usr/bin/env bash
# =============================================================================
# DEMO PHASE 2 — Same broken system, now with observability ON
#
# What happens:
#   - INTRODUCE_LATENCY_BUG=true  → bottleneck still active
#   - ENABLE_OBSERVABILITY=true   → ADOT sidecar exports to X-Ray
#   - Send 20 requests → X-Ray reveals external_validation span as root cause
#
# Talking point:
#   "Same bug. Same latency. But now we can see WHY."
#   Open X-Ray and show the waterfall — external_validation dominates.
# =============================================================================
set -euo pipefail

API="https://b10v2dz7zd.execute-api.us-east-2.amazonaws.com"
REGION="us-east-2"
XRAY_URL="https://${REGION}.console.aws.amazon.com/xray/home?region=${REGION}#/traces"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  PHASE 2: Latency bug + observability ON"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Step 1: Enable observability (keep latency bug) ───────────────────────────
echo "▶ Deploying: latency bug=ON, observability=ON..."
cd "$(dirname "$0")/../terraform/envs/demo"
terraform apply -auto-approve \
  -var="introduce_latency_bug=true" \
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
echo "   ✓ ECS service stable with ADOT sidecar"

cd "$(dirname "$0")"

# ── Step 2: Send load ──────────────────────────────────────────────────────────
echo ""
echo "▶ Sending 20 requests..."
echo ""

PASS=0; FAIL=0

for i in $(seq 1 20); do
  START=$(date +%s%3N)
  RESP=$(curl -s -o /tmp/resp.json -w "%{http_code}" \
    -X POST "$API/ingest" \
    -H "Content-Type: application/json" \
    -d "{\"source\":\"demo-phase2\",\"event_type\":\"data.ingested\",\"payload\":{\"seq\":$i}}")
  END=$(date +%s%3N)
  MS=$((END - START))

  if [ "$RESP" = "202" ]; then
    RECORD_ID=$(cat /tmp/resp.json | python3 -c "import json,sys; print(json.load(sys.stdin).get('record_id','?'))")
    printf "  [%02d] ✓ %dms  %s\n" "$i" "$MS" "$RECORD_ID"
    PASS=$((PASS + 1))
  else
    printf "  [%02d] ✗ HTTP %s\n" "$i" "$RESP"
    FAIL=$((FAIL + 1))
  fi
done

# ── Step 3: Show X-Ray evidence ────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: $PASS ok / $FAIL failed"
echo ""
echo "  🔍 Open X-Ray to see the root cause:"
echo "     $XRAY_URL"
echo ""
echo "  Look for: process_record > external_validation"
echo "  That span will be 2000ms+. That's your bottleneck."
echo ""

# Show most recent trace IDs from logs
echo "  Recent trace IDs from processor:"
aws logs filter-log-events \
  --log-group-name /ecs/obs-talk-demo/processor \
  --region "$REGION" \
  --start-time $(($(date +%s%3N) - 300000)) \
  --filter-pattern "{ $.message = \"Record processed\" }" \
  --query 'events[*].message' \
  --output text 2>/dev/null | \
  python3 -c "
import sys, json
for line in sys.stdin:
    try:
        d = json.loads(line.strip())
        print(f'  trace_id={d.get(\"trace_id\",\"?\")}  duration={d.get(\"duration_ms\",\"?\")}ms')
    except: pass
" | tail -5

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next: run phase3_fix.sh"
