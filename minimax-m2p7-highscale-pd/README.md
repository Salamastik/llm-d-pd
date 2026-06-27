# MiniMax-M2.7 — Very-High-Scale P/D Disaggregation on llm-d

Ideal deployment for [`MiniMaxAI/MiniMax-M2.7`](https://huggingface.co/MiniMaxAI/MiniMax-M2.7)
(~229B-param MoE) at very high scale, with **every llm-d optimization turned on**:

| Optimization | Where | How |
| --- | --- | --- |
| **Prefill/Decode disaggregation** | model | NIXL connector (`kv_role: kv_both`), separate P and D deployments |
| **Tiered KV CPU offloading** | model | vLLM `OffloadingConnector`, 100 GiB CPU/pod, stacked on NIXL via **MultiConnector** |
| **Precise prefix-cache-aware routing** | router/EPP | `precise-prefix-cache-scorer` fed by vLLM KV events over ZMQ |
| **Load-aware routing** | router/EPP | `kv-cache-utilization-scorer` + `queue-scorer` |
| **P/D-aware scheduling** | router/EPP | `pd-profile-handler` + `prefix-based-pd-decider` |
| **MoE wide expert parallelism** | model | `--enable-expert-parallel` |
| **Chunked prefill** | model | `--enable-chunked-prefill` |
| **FP8 KV cache** | model | `--kv-cache-dtype fp8` |
| **CUDA graphs** | model | `cudagraph_mode: PIECEWISE` |
| **High-scale mesh tuning** | gateway | Istio `DestinationRule` large conn-pools + long timeouts |

> Built by copying the **original** upstream charts verbatim and layering
> override files on top — exactly the requested pattern. Never edit the vendored
> charts; all customization lives in `overrides/*.sand.yaml` and `istio/`.

---

## ⚠️ Feasibility — read this first

### 1. Istio 1.27.6 will NOT work. Istio 1.28.6 is required. (proven)

You asked to use **Istio 1.27.6**, and to prove it if that's impossible. It is impossible, and here is the proof:

- The llm-d `inferencepool` chart (v1.3.1, vendored here) emits an InferencePool in
  the **stable** API group **`inference.networking.k8s.io/v1`**. Verified in the
  rendered output of this chart:
  ```
  apiVersion: "inference.networking.k8s.io/v1"
  kind: InferencePool
  ```
  (it is also the chart default: `inferencepool/values.yaml` → `inferencePool.apiVersion: inference.networking.k8s.io/v1`.)
- **Istio 1.27.x** added Gateway API Inference Extension support but only for the
  **alpha** InferencePool (`inference.networking.x-k8s.io/v1alpha2`). It does not
  reconcile the stable `v1` pool, so the Gateway never wires ext-proc to the EPP.
- **Istio 1.28.0** change notes: *"Added support for `InferencePool` v1"* and
  *"Removed support for `InferencePool` alpha and release candidate versions."*

So the chart's `v1` pool is recognized **only on Istio ≥ 1.28** → use **1.28.6**.
The install manifest is provided at [`istio/istio-1.28.6.install.yaml`](./istio/istio-1.28.6.install.yaml).

> If you were forced to stay on 1.27.x you would have to (a) pin the chart to the
> alpha pool (`inferencePool.apiVersion: inference.networking.x-k8s.io/v1alpha2`)
> **and** (b) install the alpha GAIE CRDs instead of `v1-manifests.yaml`. That is a
> downgrade llm-d does not ship or test — not recommended. Move to 1.28.6.

Sources:
- <https://istio.io/latest/blog/2025/inference-extension-support/>
- <https://istio.io/latest/news/releases/1.28.x/announcing-1.28/change-notes/>

### 2. This cannot actually run on the current `minikube` (no GPUs)

The active cluster is single-node `minikube` (docker driver): **8 CPU, ~12 GiB
RAM, 0 GPUs**, no NVIDIA driver, no Istio, no Gateway/Inference CRDs. This
deployment needs **48 H100s** (see topology), 320 GiB RAM and 48 CPU *per pod*.
The model-server pods would sit `Pending` (Unschedulable) forever — a hardware
limit, not a config bug. These artifacts are therefore **validated by rendering**
(`helm template`, `helm lint`, `kubectl kustomize`) rather than applied. Deploy
them on a real H100 fleet.

### 3. 4×H100 per instance ⇒ FP8 weights are mandatory (memory math)

MiniMax-M2.7 ≈ 229B params. Per instance = 4×H100 = **320 GiB** HBM.

| Precision | Weights | Fits in 320 GiB? |
| --- | --- | --- |
| BF16 | ~458 GiB | ❌ no (exceeds 4 GPUs) |
| FP8  | ~229 GiB | ✅ yes (~91 GiB left for KV + activations + CUDA graphs) |

So `modelArtifacts.uri` must point at an **FP8 checkpoint** of M2.7. If MiniMaxAI
publishes one (e.g. `MiniMax-M2.7-FP8`), use it; otherwise quantize, or raise TP
beyond 4. The override ships pointing at the base repo with this note inline.

---

## Topology (ideal high-scale layout)

```
                         Internet / clients
                                 │
                    ┌────────────▼────────────┐
                    │  Istio Gateway (1.28.6)  │  ENABLE_GATEWAY_API_INFERENCE_EXTENSION
                    │  + DestinationRule (HA)  │  3 proxy replicas, 256k conn pool
                    └────────────┬────────────┘
                                 │ ext-proc
                    ┌────────────▼────────────┐
                    │   llm-d EPP (router)     │  2 replicas (HA)
                    │  precise prefix-cache    │◄──── KV events (ZMQ :5557)
                    │  + P/D decider + load    │
                    └──────┬───────────┬───────┘
            prefill profile│           │decode profile
              ┌────────────▼──┐   ┌────▼─────────────┐
              │ PREFILL ×4    │   │ DECODE ×8         │
              │ TP=4 (4×H100) │   │ TP=4 (4×H100)     │
              │ NIXL + CPU    │──▶│ NIXL + CPU offload│   KV transfer over NIXL
              │ offload 100GB │   │ + routing sidecar │
              └───────────────┘   └───────────────────┘
              16 H100 (prefill)        32 H100 (decode)        = 48 H100 total
```

P/D ratio, replicas and TP are the scale knobs — edit
`overrides/model.values.sand.yaml` (`prefill.replicas`, `decode.replicas`,
`*.parallelism.tensor`) and the EPP `threshold` in
`overrides/router.values.sand.yaml`.

---

## Layout (original chart + override per layer)

```
deploy/minimax-m2p7-highscale-pd/
├── Chart.yaml                       # umbrella; vendors the 3 ORIGINAL subcharts
├── charts/                          # ORIGINAL upstream charts, verbatim (do not edit)
│   ├── llm-d-infra-v1.3.6.tgz
│   ├── inferencepool-v1.3.1.tgz
│   └── llm-d-modelservice-v0.4.7.tgz
├── templates/  values.yaml          # umbrella glue + upstream defaults
├── overrides/                       # ← all customization lives here
│   ├── gateway.values.sand.yaml     # LAYER 1: Istio provider + high-scale conn pool
│   ├── router.values.sand.yaml      # LAYER 2: EPP precise prefix + P/D
│   └── model.values.sand.yaml       # LAYER 3: P/D + CPU offload + MoE opts (M2.7)
└── istio/
    ├── istio-1.28.6.install.yaml    # Istio control-plane install (required)
    ├── base/  original/             # ORIGINAL llm-d istio gateway recipe, verbatim
    └── kustomization.yaml           # high-scale overlay (references original/)
```

---

## Validate (no cluster needed)

```bash
cd deploy/minimax-m2p7-highscale-pd

# Helm: render the umbrella with the three layered overrides
helm template m2p7 . \
  -n llm-d-minimax-m2p7 \
  -f overrides/gateway.values.sand.yaml \
  -f overrides/router.values.sand.yaml \
  -f overrides/model.values.sand.yaml

helm lint . -f overrides/gateway.values.sand.yaml \
            -f overrides/router.values.sand.yaml \
            -f overrides/model.values.sand.yaml

# Kustomize: render the high-scale Istio gateway overlay
kubectl kustomize istio/
```

All three pass in this repo (helm: 22 objects, lint 0 failures; kustomize: 2 objects).

---

## Deploy (on a real H100 cluster)

```bash
export NAMESPACE=llm-d-minimax-m2p7

# 0) ONE-TIME cluster bootstrap — CRDs + Istio 1.28.6 + namespace + hf-token.
#    Everything you install once lives in bootstrap/ (see bootstrap/README.md).
export HF_TOKEN=hf_xxxxxxxx
( cd bootstrap && ./install.sh )       # idempotent; ./install.sh verify to re-check

# 3) (optional) high-scale shared Istio Gateway recipe — only if you are NOT
#    using the umbrella chart's own infra-rendered gateway:
#    kubectl apply -k istio/ -n ${NAMESPACE}

# 4) Deploy the umbrella (gateway + router + model in one release)
helm dependency build .
helm upgrade --install m2p7 . -n ${NAMESPACE} \
  -f overrides/gateway.values.sand.yaml \
  -f overrides/router.values.sand.yaml \
  -f overrides/model.values.sand.yaml

# 5) Wait for the Gateway to be programmed, then send a request
export IP=$(kubectl get gateway m2p7-inference-gateway -n ${NAMESPACE} \
  -o jsonpath='{.status.addresses[0].value}')
curl -X POST http://${IP}/v1/completions -H 'Content-Type: application/json' \
  -d '{"model":"MiniMaxAI/MiniMax-M2.7","prompt":"How are you today?"}' | jq
```

> The umbrella's `infra` subchart renders the Istio `Gateway`
> (`m2p7-inference-gateway`), `DestinationRule` and `Telemetry`, so step 3 is
> only for a cluster-wide **shared** gateway. Pick one Gateway — don't run both.

## Cleanup

```bash
helm uninstall m2p7 -n ${NAMESPACE}
# kubectl delete -k istio/ -n ${NAMESPACE}   # if you used the shared gateway
# istioctl uninstall --purge -y && kubectl delete ns istio-system
```
