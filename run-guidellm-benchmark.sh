#!/usr/bin/env bash
set -euo pipefail

DATA_FILE="${DATA_FILE:-$PWD/guidellm-data/pride-large.txt}"
RESULTS_DIR="${RESULTS_DIR:-$PWD/guidellm-results}"
TARGET_URL="${TARGET_URL:-http://127.0.0.1:18000/v1}"

if [[ ! -f "$DATA_FILE" ]]; then
  echo "DATA_FILE not found: $DATA_FILE" >&2
  exit 1
fi

mkdir -p "$RESULTS_DIR"

# Start port-forward and ensure cleanup
kubectl -n llm-d-system port-forward svc/llm-d-infra-inference-gateway 18000:80 >/tmp/port-forward.log 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT

# Wait for gateway
for i in {1..15}; do
  if curl -sS "$TARGET_URL/v1/models" >/tmp/models.json; then
    break
  fi
  sleep 1
  if ! kill -0 $PF_PID 2>/dev/null; then
    echo "port-forward died. Check /tmp/port-forward.log" >&2
    exit 1
  fi
done

# Run benchmark (host network so container can reach localhost:18000)
docker run --rm --network host \
  -v "$PWD/guidellm-data:/data:ro" \
  -v "$RESULTS_DIR:/results:rw" \
  -w /results \
  ghcr.io/vllm-project/guidellm:latest \
  guidellm benchmark \
    --target "$TARGET_URL" \
    --request-type chat_completions \
    --data "/data/$(basename "$DATA_FILE")" \
    --profile sweep \
    --max-seconds 60

echo "Done. Results in: $RESULTS_DIR"
