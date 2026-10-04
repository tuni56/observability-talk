#!/usr/bin/env bash
# =============================================================================
# Load generator — continuous traffic for dashboard population
#
# Usage:
#   ./load_generator.sh          # 1 req/s, runs until Ctrl+C
#   ./load_generator.sh 5 60     # 5 req/s for 60 seconds
# =============================================================================
set -euo pipefail

API="https://b10v2dz7zd.execute-api.us-east-2.amazonaws.com"
RPS="${1:-1}"
DURATION="${2:-0}"  # 0 = run forever

INTERVAL=$(python3 -c "print(1/$RPS)")
COUNT=0
START_TIME=$(date +%s)

echo "Load generator: ${RPS} req/s  $([ $DURATION -gt 0 ] && echo "for ${DURATION}s" || echo "until Ctrl+C")"
echo ""

while true; do
  ELAPSED=$(( $(date +%s) - START_TIME ))
  [ $DURATION -gt 0 ] && [ $ELAPSED -ge $DURATION ] && break

  RESP=$(curl -s -o /tmp/lg_resp.json -w "%{http_code}" \
    -X POST "$API/ingest" \
    -H "Content-Type: application/json" \
    -d "{\"source\":\"load-gen\",\"event_type\":\"data.ingested\",\"payload\":{\"seq\":$COUNT}}")

  COUNT=$((COUNT + 1))

  if [ "$RESP" = "202" ]; then
    printf "\r  sent: %d  status: ok  elapsed: %ds   " "$COUNT" "$ELAPSED"
  else
    printf "\r  sent: %d  status: HTTP%s  elapsed: %ds" "$COUNT" "$RESP" "$ELAPSED"
  fi

  sleep "$INTERVAL"
done

echo ""
echo "Done. Sent $COUNT requests."
