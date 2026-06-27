# Ideal Deployment Guide — MiniMax-M2.7, Very-High-Scale, P/D Disaggregated

A from-scratch, **canonical** llm-d deployment for
[`MiniMaxAI/MiniMax-M2.7`](https://huggingface.co/MiniMaxAI/MiniMax-M2.7)
(~229B-param MoE) at very high scale with every optimization the well-lit-path
guides expose. This guide is synthesized **only** from the in-repo guides and
READMEs (cited inline) and the canonical versions in
[`guides/env.sh`](../guides/env.sh) — it does **not** use the older
`minimax-m2p5-precise-pd` umbrella chart or the `llm-d-infra` umbrella. It uses
the modern three-layer pattern: **Istio Gateway recipe → `llm-d-router-gateway`
chart → model-server Kustomize overlays.**

---

## 0. Target & design decisions (grounded in the guides)

| Decision | Value | Source / rationale |
| --- | --- | --- |
| Pattern | Prefill/Decode disaggregated, gateway mode | [`guides/pd-disaggregation`](../guides/pd-disaggregation/README.md) |
| Per-instance HW | 4× H100, TP=4 (both P and D) | your constraint |
| Precision | **FP8 weights** (mandatory) | 229B BF16 ≈458 GiB > 320 GiB (4×80); FP8 ≈229 GiB fits |
| High-scale layout | xPyD, P=more replicas/less TP, D=more TP | "P/D Best Practices", [`pd-disaggregation`](../guides/pd-disaggregation/README.md#pd-best-practices) |
| Example scale | 4× prefill + 8× decode (TP=4) = **48 H100** | tune `replicas`; see §7 |
| Routing | precise prefix-cache + load + P/D aware | [`precise-prefix-cache-routing`](../guides/precise-prefix-cache-routing/README.md), [`pd-disaggregation`](../guides/pd-disaggregation/router/pd-disaggregation.values.yaml) |
| KV offload | CPU tier via vLLM `OffloadingConnector` | [`tiered-prefix-cache`](../guides/tiered-prefix-cache/README.md) |
| Gateway | **Istio 1.28.6** (NOT 1.27.x) | InferencePool **v1** needs Istio ≥1.28 (see §1.2) |

### Canonical versions (from `guides/env.sh` + recipe components)

```bash
GATEWAY_API_VERSION=v1.5.1
GAIE_VERSION=v1.5.0                                   # InferencePool v1 manifests
ROUTER_CHART_VERSION=v0.9.0
ROUTER_GATEWAY_CHART=oci://ghcr.io/llm-d/charts/llm-d-router-gateway
ROUTING_SIDECAR_IMAGE=ghcr.io/llm-d/llm-d-router-disagg-sidecar:v0.9.0  # NOT the old llm-d-routing-sidecar:v0.6.0
ISTIO_VERSION=1.28.6
```

> **vLLM image:** the canonical PD overlay's `gpu-vllm` component pins
> **`vllm/vllm-openai:v0.23.0`** (upstream vLLM — *not* `llm-d-cuda`). Confirm
> your chosen tag is recent enough to include the MiniMax-M2 tool/reasoning
> parsers **and** the `OffloadingConnector`/`MultiConnector`, and bump it in the
> overlay's `images:` block if needed. Verify before rollout (see §6 note).

---

## 1. One-time cluster prerequisites

> From [`helpers/client-setup`](../helpers/client-setup/README.md),
> [`docs/infrastructure/gateway/install-crds.md`](../docs/infrastructure/gateway/install-crds.md),
> and [`docs/infrastructure/gateway/istio.md`](../docs/infrastructure/gateway/istio.md).

```bash
export REPO_ROOT=$(git rev-parse --show-toplevel)
source ${REPO_ROOT}/guides/env.sh
export GUIDE_NAME="minimax-m2p7-highscale-pd"
export NAMESPACE="llm-d-minimax-m2p7"
export MODEL_NAME="MiniMaxAI/MiniMax-M2.7"
export PROVIDER_NAME=istio
```

### 1.1 GPUs (NVIDIA GPU Operator)

Nodes must advertise `nvidia.com/gpu`. On a fresh H100 fleet, once per cluster:

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia && helm repo update
helm install --wait gpu-operator nvidia/gpu-operator -n gpu-operator --create-namespace
```

### 1.2 Gateway API + Inference Extension CRDs

```bash
bash ${REPO_ROOT}/guides/recipes/gateway/install-gateway-crds.sh
# installs Gateway API v1.5.1 (standard) + GAIE v1.5.0 v1-manifests
kubectl api-resources --api-group=inference.networking.k8s.io   # must list inferencepools (v1)
```

### 1.3 Istio 1.28.6 — **why not 1.27.6**

The charts emit the **stable** `InferencePool` (`inference.networking.k8s.io/v1`).
**Istio 1.27.x only supports the alpha pool** (`…x-k8s.io/v1alpha2`); **Istio
1.28.0 added `InferencePool v1` and removed alpha support.** So 1.27.6 silently
never wires the Gateway to the EPP — use 1.28.6.
(Sources: istio.io/latest/blog/2025/inference-extension-support/ and the Istio 1.28 change notes.)

```bash
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.28.6 sh -
export PATH="$PWD/istio-1.28.6/bin:$PATH"
istioctl install -y --set values.pilot.env.ENABLE_GATEWAY_API_INFERENCE_EXTENSION=true
istioctl version    # confirm 1.28.6
```

### 1.4 Namespace + HuggingFace token

> [`helpers/hf-token.md`](../helpers/hf-token.md)

```bash
kubectl create namespace ${NAMESPACE}
kubectl create secret generic llm-d-hf-token -n ${NAMESPACE} \
  --from-literal="HF_TOKEN=${HF_TOKEN}"
```

---

## 2. Layer 1 — Deploy the Istio Gateway

> [`docs/infrastructure/gateway/istio.md`](../docs/infrastructure/gateway/istio.md) +
> [`guides/recipes/gateway/istio`](../guides/recipes/gateway/istio). One shared
> Gateway per cluster; each guide attaches its own HTTPRoute.

```bash
kubectl apply -k ${REPO_ROOT}/guides/recipes/gateway/istio -n ${NAMESPACE}
kubectl get gateway llm-d-inference-gateway -n ${NAMESPACE}   # wait for PROGRAMMED=True
```

**High-scale mesh tuning** — overlay a `DestinationRule` (large conn pools / long
timeouts) and raise the gateway proxy replicas/resources, as the gateway recipe's
ConfigMap allows. (Pattern from the istio recipe's `configmap.yaml`.)

---

## 3. Layer 2 — Deploy the Router (EPP) in Gateway Mode

> Command shape from [`pd-disaggregation` → Gateway Mode](../guides/pd-disaggregation/README.md);
> base values from [`recipes/router/base.values.yaml`](../guides/recipes/router/base.values.yaml).

Create `router/${GUIDE_NAME}.values.yaml` — this is the **router-gateway chart
(v0.9.0) `router.epp` schema** (`apiVersion: llm-d.ai/v1alpha1`), composing **P/D
profiles + precise prefix-cache + load scorers**:

```yaml
router:
  epp:
    replicas: 2                         # HA at high scale
    pluginsConfigFile: "pd-precise-config.yaml"
    pluginsCustomConfig:
      pd-precise-config.yaml: |
        apiVersion: llm-d.ai/v1alpha1
        kind: EndpointPickerConfig
        plugins:
        - type: disagg-headers-handler
        - type: prefix-based-pd-decider          # route by cached-prefix length
        - type: disagg-profile-handler
          parameters:
            deciderPluginName: prefix-based-pd-decider
            threshold: 256                        # P/D split; tune to ISL/OSL
        - type: prefill-filter
        - type: decode-filter
        - type: precise-prefix-cache-scorer       # KV-events based (precise)
        - type: queue-scorer
        - type: kv-cache-utilization-scorer
        - type: active-request-scorer
        schedulingProfiles:
        - name: prefill
          plugins:
          - pluginRef: prefill-filter
          - pluginRef: precise-prefix-cache-scorer
            weight: 3
          - pluginRef: queue-scorer
            weight: 2
          - pluginRef: kv-cache-utilization-scorer
            weight: 2
        - name: decode
          plugins:
          - pluginRef: decode-filter
          - pluginRef: precise-prefix-cache-scorer
            weight: 3
          - pluginRef: active-request-scorer
            weight: 2
  modelServers:
    matchLabels:
      llm-d.ai/guide: "minimax-m2p7-highscale-pd"
```

> The precise (KV-events) scorer + its tokenizer sidecar/ZMQ wiring follow
> [`precise-prefix-cache-routing`](../guides/precise-prefix-cache-routing/README.md).
> If your router build doesn't ship `precise-prefix-cache-scorer`, fall back to
> the approximate `prefix-cache-scorer` used in the stock
> [`pd-disaggregation.values.yaml`](../guides/pd-disaggregation/router/pd-disaggregation.values.yaml).

Install (gateway mode):

```bash
helm install ${GUIDE_NAME} ${ROUTER_GATEWAY_CHART} \
  -f ${REPO_ROOT}/guides/recipes/router/base.values.yaml \
  -f ${REPO_ROOT}/guides/recipes/router/features/httproute-flags.yaml \
  -f router/${GUIDE_NAME}.values.yaml \
  --set provider.name=${PROVIDER_NAME} \
  -n ${NAMESPACE} --version ${ROUTER_CHART_VERSION}
```

Optional monitoring: add `-f ${REPO_ROOT}/guides/recipes/router/features/monitoring.values.yaml`.

---

## 4. Layer 3 — Deploy the Model Servers (P/D, Kustomize overlays)

> Structure from [`pd-disaggregation/modelserver/gpu/vllm`](../guides/pd-disaggregation/modelserver/gpu/vllm);
> sidecar image from [`recipes/modelserver/components/images/routing-sidecar`](../guides/recipes/modelserver/components/images/routing-sidecar/kustomization.yaml).

Create an overlay `modelserver/` with a base + `patch-prefill.yaml` /
`patch-decode.yaml`. Both pods run TP=4; the **decode** pod also runs the
`llm-d-router-disagg-sidecar` proxy.

### 4.1 The vLLM args (all optimizations)

Shared flags for **both** prefill and decode:

```yaml
- --trust-remote-code
- --tensor-parallel-size=4            # 4× H100
- --block-size=128
- --max-model-len=131072
- --kv-cache-dtype=fp8                # FP8 KV cache → more KV capacity
- --enable-prefix-caching            # prefix caching (emits KV events for the precise scorer)
- --enable-chunked-prefill           # chunked prefill
- --enable-expert-parallel           # MoE wide expert parallelism
- --enable-auto-tool-choice
- --tool-call-parser=minimax_m2      # MiniMax-M2 family (from the M2 HF deploy guide)
- --reasoning-parser=minimax_m2_append_think
- --compilation-config={"cudagraph_mode":"PIECEWISE"}   # CUDA graphs
```

### 4.2 P/D disaggregation **+** CPU offloading (the one composed knob)

Canonical PD is plain NIXL:
`{"kv_connector":"NixlConnector","kv_role":"kv_both"}`
([pd-disaggregation base patches](../guides/pd-disaggregation/modelserver/gpu/vllm/base/patch-prefill.yaml)).
Canonical CPU offload is `OffloadingConnector` alone
([tiered-prefix-cache native](../guides/tiered-prefix-cache/modelserver/gpu/vllm/native/cpu/base/patch-vllm.yaml)).

To get **both at once**, stack them with vLLM **MultiConnector**. Verified against
vLLM source (`multi_connector.py`): the sub-connectors live under
`kv_connector_extra_config.connectors`, and each entry is a full
`KVTransferConfig` (its own `kv_connector` + optional `kv_connector_extra_config`):

```yaml
- >-
  --kv-transfer-config={"kv_connector":"MultiConnector","kv_role":"kv_both",
  "kv_connector_extra_config":{"connectors":[
    {"kv_connector":"NixlConnector","kv_role":"kv_both"},
    {"kv_connector":"OffloadingConnector","kv_role":"kv_both",
     "kv_connector_extra_config":{"cpu_bytes_to_use":107374182400}}
  ]}}
```

> ⚠️ **Validate this combo on your image before production.** NIXL-for-P/D +
> `OffloadingConnector`-for-CPU via `MultiConnector` is supported by vLLM, but
> **no llm-d guide ships this exact combination** — every PD guide uses NIXL
> alone. If it misbehaves, ship them un-composed: NIXL-only for P/D (drop CPU
> offload), or a non-disaggregated tier that uses `OffloadingConnector` only.

### 4.3 KV events (feeds the precise prefix-cache scorer)

```yaml
- >-
  --kv-events-config={"enable_kv_cache_events":true,"publisher":"zmq",
  "endpoint":"tcp://${GUIDE_NAME}-epp.${NAMESPACE}.svc.cluster.local:5557",
  "topic":"kv@$(POD_IP)@MiniMaxAI/MiniMax-M2.7"}
```

### 4.4 Pin the sidecar image + apply

In the overlay's `kustomization.yaml`, include the canonical sidecar component
(`llm-d-router-disagg-sidecar:v0.9.0`) and set replicas / labels:

```yaml
components:
  - ../../recipes/modelserver/components/images/routing-sidecar
# prefill.replicas=4, decode.replicas=8, label llm-d.ai/guide=minimax-m2p7-highscale-pd
```

```bash
kubectl apply -k modelserver/ -n ${NAMESPACE}
```

---

## 5. Monitoring (optional)

> [`pd-disaggregation` → Enable Monitoring](../guides/pd-disaggregation/README.md)

```bash
kubectl apply -n ${NAMESPACE} -k ${REPO_ROOT}/guides/recipes/modelserver/components/monitoring-pd
```

---

## 6. Verify

```bash
export IP=$(kubectl get gateway llm-d-inference-gateway -n ${NAMESPACE} \
  -o jsonpath='{.status.addresses[0].value}')
curl -X POST http://${IP}/v1/completions -H 'Content-Type: application/json' \
  -d '{"model":"MiniMaxAI/MiniMax-M2.7","prompt":"How are you today?"}' | jq
```

> If pods crash on unknown args (`minimax_m2*`, `OffloadingConnector`,
> `MultiConnector`), your `llm-d-cuda` tag is too old — bump it (§0).

---

## 7. Scale & tune (xPyD)

> "P/D Best Practices", [`pd-disaggregation`](../guides/pd-disaggregation/README.md#pd-best-practices).

- **xPyD ratio** — match prefill:decode to your ISL:OSL. Long-input/agentic
  (high ISL) → more prefill; long-output → more decode. Start 4P:8D, watch TTFT
  (prefill-bound) vs ITL (decode-bound).
- **EPP `threshold`** (§3) — raises/lowers when a request is split P/D.
- **`cpu_bytes_to_use`** (§4.2) — size the CPU KV tier to node RAM (here 100 GiB).
- **`--max-model-len` / `--kv-cache-dtype`** — FP8 KV already maximizes on-GPU KV;
  CPU offload extends the effective working set for multi-turn/long-context.

## 8. Benchmark

> [`pd-disaggregation` → Benchmarking](../guides/pd-disaggregation/README.md#benchmarking) with `llmdbenchmark`.

```bash
curl -sSL https://raw.githubusercontent.com/llm-d/llm-d-benchmark/main/install.sh | bash
# then: llmdbenchmark ... --gateway-class istio --model MiniMaxAI/MiniMax-M2.7 ...
```

## 9. Cleanup

```bash
helm uninstall ${GUIDE_NAME} -n ${NAMESPACE}
kubectl delete -k modelserver/ -n ${NAMESPACE}
kubectl delete -k ${REPO_ROOT}/guides/recipes/gateway/istio -n ${NAMESPACE}
```
