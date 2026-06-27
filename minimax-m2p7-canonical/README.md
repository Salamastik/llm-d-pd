# minimax-m2p7-canonical — ready-to-run, self-contained

Canonical, validated artifacts for deploying
[`MiniMaxAI/MiniMax-M2.7`](https://huggingface.co/MiniMaxAI/MiniMax-M2.7) (~229B
MoE) at very high scale with P/D disaggregation and every llm-d optimization.
Built purely from the upstream llm-d well-lit-path guides (no legacy umbrella
chart, no `llm-d-infra`): **Istio gateway recipe → `llm-d-router-gateway` chart
(v0.9.0) → model-server Kustomize overlay on the canonical PD bases**.

Full rationale, topology, FP8 math and the Istio-1.28 requirement are in
[`IDEAL-deploy-guide.md`](./IDEAL-deploy-guide.md).

```
minimax-m2p7-canonical/
├── IDEAL-deploy-guide.md
├── router/
│   ├── base.values.yaml                        # vendored upstream (recipes/router)
│   ├── httproute-flags.yaml                     # vendored upstream
│   └── minimax-m2p7-highscale-pd.values.yaml    # P/D + precise prefix + load (router.epp)
└── modelserver/
    ├── kustomization.yaml                       # REMOTE bases → builds standalone
    ├── patch-prefill.yaml                        # TP=4, ×4, M2.7 flags, MultiConnector (NIXL+CPU offload)
    └── patch-decode.yaml                         # TP=4, ×8, +routing sidecar, port 8200
```

This folder is **self-contained**: the model-server overlay pulls its bases by
remote ref from `github.com/llm-d/llm-d`, and the upstream router base-values are
vendored here — no local llm-d checkout required.

## Canonical versions

`GAIE v1.5.0` · `llm-d-router-gateway v0.9.0` · `llm-d-router-disagg-sidecar:v0.9.0`
· `vllm/vllm-openai:v0.23.0` · **Istio 1.28.6** (InferencePool v1 needs ≥1.28).

## Deploy

```bash
export NAMESPACE=llm-d-minimax-m2p7
export ROUTER_GATEWAY_CHART=oci://ghcr.io/llm-d/charts/llm-d-router-gateway
export ROUTER_CHART_VERSION=v0.9.0

# 0) ONE-TIME prereqs (GPU operator, Gateway+GAIE CRDs, Istio 1.28.6, hf-token):
#    see IDEAL-deploy-guide.md §1.

# 1) Gateway (remote recipe — no checkout needed)
kubectl apply -k "github.com/llm-d/llm-d//guides/recipes/gateway/istio?ref=main" -n ${NAMESPACE}

# 2) Router (EPP) — gateway mode
helm install minimax-m2p7-highscale-pd ${ROUTER_GATEWAY_CHART} \
  -f router/base.values.yaml \
  -f router/httproute-flags.yaml \
  -f router/minimax-m2p7-highscale-pd.values.yaml \
  --set provider.name=istio -n ${NAMESPACE} --version ${ROUTER_CHART_VERSION}

# 3) Model servers
kubectl apply -k modelserver/ -n ${NAMESPACE}
```

## Validation status (rendered, no cluster)

| Artifact | Tool | Result |
| --- | --- | --- |
| `modelserver/` (remote bases) | `kubectl kustomize` | ✅ 2 Deployments + SA; TP=4; GPU=4; `vllm/vllm-openai:v0.23.0` + `llm-d-router-disagg-sidecar:v0.9.0` |
| `router/…values.yaml` | `helm template llm-d-router-gateway:v0.9.0` | ✅ InferencePool **v1**, HTTPRoute, DestinationRule, EPP plugins (disagg + precise prefix) |

> ⚠️ One composed knob is **not** covered by any llm-d guide: NIXL (P/D) +
> `OffloadingConnector` (CPU) via `MultiConnector`. Shape verified vs vLLM source,
> but validate on your image, or ship them un-composed. See IDEAL guide §4.2.
>
> Pin `?ref=main` to a release tag for reproducible builds.
