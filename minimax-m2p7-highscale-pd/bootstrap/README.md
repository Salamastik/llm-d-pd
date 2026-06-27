# One-time cluster bootstrap

Everything here installs **once per cluster** (except the namespace+secret, which
is once per namespace). After this, you only ever run `helm upgrade --install`
(see [`../README.md`](../README.md) §Deploy) — no re-bootstrapping.

## TL;DR

```bash
export HF_TOKEN=hf_xxxxxxxx                 # your HuggingFace token
export NAMESPACE=llm-d-minimax-m2p7         # optional; this is the default
./install.sh                               # does all 4 steps + verifies
```

Run it again any time — it is idempotent. To check state only: `./install.sh verify`.

---

## What gets installed, and why

| # | Component | Scope | Why it's needed | Version |
|---|-----------|-------|-----------------|---------|
| 1 | **Gateway API CRDs** (standard channel) | cluster | Defines `GatewayClass`, `Gateway`, `HTTPRoute` — the ingress objects the chart creates | `v1.5.1` |
| 2 | **Gateway API Inference Extension CRDs** | cluster | Defines `InferencePool` **v1** + `InferenceObjective` — the AI-aware routing objects (the EPP/router backend) | `v1.5.0` (`v1-manifests.yaml`) |
| 3 | **Istio control plane** | cluster | The Gateway provider (Envoy data plane) + ext-proc wiring to the EPP. **Must be ≥ 1.28** — see below | `1.28.6` |
| 4 | **Namespace + `hf-token` secret** | namespace | Target namespace and the HuggingFace pull token (key `HF_TOKEN`) the model & EPP mount | — |

### Exactly which CRDs (the resource kinds)

**From Gateway API `standard-install.yaml` (v1.5.1):**
- `gatewayclasses.gateway.networking.k8s.io`
- `gateways.gateway.networking.k8s.io`
- `httproutes.gateway.networking.k8s.io`
- `referencegrants.gateway.networking.k8s.io`
- `grpcroutes.gateway.networking.k8s.io`

**From Gateway API Inference Extension `v1-manifests.yaml` (v1.5.0):**
- `inferencepools.inference.networking.k8s.io` ← **the stable v1 pool** (the whole reason you need Istio 1.28)
- `inferenceobjectives.inference.networking.x-k8s.io`

> Verify after install:
> ```bash
> kubectl api-resources --api-group=gateway.networking.k8s.io
> kubectl api-resources --api-group=inference.networking.k8s.io   # must list inferencepools
> ```

### Why Istio 1.28.6 and not your 1.27.6

These charts emit `InferencePool` in the **stable** group
`inference.networking.k8s.io/v1`. **Istio 1.27.x supports only the alpha pool**
(`…x-k8s.io/v1alpha2`); **Istio 1.28.0 added `InferencePool v1` and removed alpha
support.** On 1.27.6 the Gateway silently never wires up to the EPP. Full proof +
sources in [`../README.md`](../README.md) §Feasibility. `install.sh` refuses any
Istio version below 1.28.

---

## Prerequisite: GPUs (real clusters only)

The CRDs/Istio above are lightweight and run anywhere. But to actually **schedule**
the model pods (`nvidia.com/gpu: 4` each) the cluster nodes must advertise GPUs.
On a fresh H100 cluster install the **NVIDIA GPU Operator** once:

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia && helm repo update
helm install --wait gpu-operator nvidia/gpu-operator -n gpu-operator --create-namespace
```

`./install.sh verify` warns if no node advertises `nvidia.com/gpu`. On the local
`minikube` here there are **no GPUs**, so the pods will stay `Pending` — that is
expected (this box is for rendering/validation only).

---

## Step-by-step (if you prefer manual)

```bash
# 1+2: CRDs
./install.sh crds
# or directly:
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/v1.5.0/v1-manifests.yaml

# 3: Istio 1.28.6 (downloads istioctl if missing, installs with inference ext enabled)
./install.sh istio
# or directly:
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.28.6 sh -
export PATH="$PWD/istio-1.28.6/bin:$PATH"
istioctl install -y -f ../istio/istio-1.28.6.install.yaml

# 4: namespace + secret
export HF_TOKEN=hf_xxx
./install.sh ns

# check
./install.sh verify
```

When `verify` is all ✅ (GPU warning aside), proceed to the Helm deploy in
[`../README.md`](../README.md) §"Deploy (on a real H100 cluster)" step 4.

## Uninstall (tear the cluster-scoped bits back down)

```bash
istioctl uninstall --purge -y && kubectl delete ns istio-system
kubectl delete -f https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/v1.5.0/v1-manifests.yaml
kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml
```
