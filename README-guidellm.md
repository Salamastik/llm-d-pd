# GuideLLM: Runbook (CLI + Streamlit)

This README documents two **independent** ways to run benchmarks against your
Qwen endpoint:

1. **CLI container** (`ghcr.io/vllm-project/guidellm:latest`)
2. **Streamlit Workbench** (`quay.io/rh-aiservices-bu/guidellm-wb:v1`)

You can run **either one**. You do **not** need both.

## Prereqs

1. Your model must be reachable via an OpenAI-compatible endpoint.
2. For the local setup in this repo, you should use a port‑forward to the
   inference gateway:

```bash
kubectl -n llm-d-system port-forward svc/llm-d-infra-inference-gateway 18000:80
```

Verify connectivity:

```bash
curl http://127.0.0.1:18000/v1/models
```

If that fails, **don’t** run benchmarks yet.

---

## Option A: CLI Container (GuideLLM)

### 1. Create a results directory (once)

```bash
mkdir -p /home/etty/llm-d-pd/results
chmod -R a+rwx /home/etty/llm-d-pd/results
```

### 2. Run a benchmark (works)

**Important:** The image entrypoint is already `guidellm`, so you run
`benchmark`, not `guidellm benchmark`.

```bash
docker run --rm --network host \
  -v /home/etty/llm-d-pd/results:/results:rw \
  ghcr.io/vllm-project/guidellm:latest \
  benchmark \
    --target http://127.0.0.1:18000/v1 \
    --model Qwen/Qwen2.5-0.5B-Instruct \
    --rate-type synchronous \
    --max-seconds 60 \
    --max-requests 100 \
    --data "{\"type\": \"emulated\", \"prompt_tokens\": 512, \"output_tokens\": 128}" \
    --output-path /results/qwen-benchmark.yaml \
    --processor Qwen/Qwen2.5-0.5B-Instruct
```

Results are saved in:

```
/home/etty/llm-d-pd/results/qwen-benchmark.yaml
```

---

## Option B: Streamlit Workbench (UI)

### 1. Start the container

```bash
docker run -d --name guidellm-wb --network host \
  -v /home/etty/llm-d-pd/guidellm-data:/app/data:ro \
  -v /home/etty/llm-d-pd/guidellm-results:/app/results:rw \
  quay.io/rh-aiservices-bu/guidellm-wb:v1
```

### 2. Open the UI

```
http://127.0.0.1:8501
```

### 3. UI settings that work

**Target Endpoint**

```
http://127.0.0.1:18000/v1
```

**Model Name**

```
Qwen/Qwen2.5-0.5B-Instruct
```

**Data Type**

```
custom
```

**Custom Data Config (JSON)**

This must be **valid JSON**. Use one of these:

```json
"/app/data/pride-large.txt"
```

or

```json
{"type":"custom","path":"/app/data/pride-large.txt"}
```

### 4. Where results appear in UI

After you click **Run Benchmark**:

1. A new entry appears under **Results History**.
2. You can select it under **Detailed Results** to view metrics.

### 5. Stop the UI container

```bash
docker rm -f guidellm-wb
```

---

## Common Errors

### `json.decoder.JSONDecodeError`

The “Custom Data Config” field is **not valid JSON**.

Use:

```json
"/app/data/pride-large.txt"
```

### `ConnectError / ReadError`

The target is not reachable. Check:

```bash
curl http://127.0.0.1:18000/v1/models
```

If this fails, port‑forward is down or the gateway is unhealthy.

