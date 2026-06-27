#!/usr/bin/env bash
# =============================================================================
# ONE-TIME cluster bootstrap for minimax-m2p7-highscale-pd
# -----------------------------------------------------------------------------
# Installs everything the deployment needs that is NOT part of the Helm release:
#   1. Gateway API CRDs            (standard channel, v1.5.1)
#   2. Gateway API Inference Ext.  (InferencePool v1, v1.5.0)
#   3. Istio control plane         (1.28.6 — REQUIRED, 1.27.x cannot do v1 pool)
#   4. Namespace + HuggingFace token secret
#
# Cluster-scoped steps (CRDs, Istio) are global and only need to run ONCE per
# cluster. The namespace/secret step is per-namespace. Re-running is safe
# (idempotent). On a real GPU cluster you also need the NVIDIA GPU Operator —
# see README "Prerequisite: GPUs".
#
# Usage:
#   export HF_TOKEN=hf_xxx                 # required for step 4
#   export NAMESPACE=llm-d-minimax-m2p7    # optional (this is the default)
#   ./install.sh                           # all steps
#   ./install.sh crds                      # only steps 1-2
#   ./install.sh istio                     # only step 3
#   ./install.sh ns                        # only step 4
#   ./install.sh verify                    # check everything is present
# =============================================================================
set -euo pipefail

GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.5.1}"
GAIE_VERSION="${GAIE_VERSION:-v1.5.0}"
ISTIO_VERSION="${ISTIO_VERSION:-1.28.6}"
NAMESPACE="${NAMESPACE:-llm-d-minimax-m2p7}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISTIO_INSTALL_FILE="${SCRIPT_DIR}/../istio/istio-1.28.6.install.yaml"

G="\033[32m"; R="\033[31m"; Y="\033[33m"; Z="\033[0m"
ok()   { echo -e "${G}✅ $*${Z}"; }
warn() { echo -e "${Y}⚠️  $*${Z}"; }
die()  { echo -e "${R}❌ $*${Z}" >&2; exit 1; }

command -v kubectl >/dev/null || die "kubectl not found"

install_crds() {
  echo "── [1/2] Gateway API CRDs (${GATEWAY_API_VERSION}) ───────────────────"
  kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
  echo "── [2/2] Gateway API Inference Extension CRDs (${GAIE_VERSION}, v1) ──"
  kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/${GAIE_VERSION}/v1-manifests.yaml"
  ok "CRDs installed"
}

install_istio() {
  echo "── Istio ${ISTIO_VERSION} (control plane + inference extension) ──────"
  [[ "${ISTIO_VERSION}" == 1.2[89].* || "${ISTIO_VERSION%%.*}" -gt 1 ]] \
    || die "Istio ${ISTIO_VERSION} is too old — InferencePool v1 needs >= 1.28. Use 1.28.6."
  if ! command -v istioctl >/dev/null; then
    warn "istioctl not on PATH — downloading Istio ${ISTIO_VERSION}…"
    ( cd "${SCRIPT_DIR}" && curl -L https://istio.io/downloadIstio | ISTIO_VERSION="${ISTIO_VERSION}" sh - )
    export PATH="${SCRIPT_DIR}/istio-${ISTIO_VERSION}/bin:${PATH}"
  fi
  istioctl install -y -f "${ISTIO_INSTALL_FILE}"
  istioctl version
  ok "Istio installed"
}

install_ns() {
  echo "── Namespace ${NAMESPACE} + hf-token secret ─────────────────────────"
  kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
  [[ -n "${HF_TOKEN:-}" ]] || die "HF_TOKEN env var is required for the hf-token secret"
  kubectl create secret generic hf-token -n "${NAMESPACE}" \
    --from-literal="HF_TOKEN=${HF_TOKEN}" \
    --dry-run=client -o yaml | kubectl apply -f -
  ok "Namespace + secret ready"
}

verify() {
  echo "── Verifying ────────────────────────────────────────────────────────"
  kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1 && ok "Gateway API CRDs present" || die "Gateway API CRDs MISSING"
  kubectl get crd inferencepools.inference.networking.k8s.io >/dev/null 2>&1 && ok "InferencePool v1 CRD present" || die "InferencePool v1 CRD MISSING (run: ./install.sh crds)"
  kubectl get pods -n istio-system 2>/dev/null | grep -q istiod && ok "istiod running" || warn "istiod not found (run: ./install.sh istio)"
  kubectl get ns "${NAMESPACE}" >/dev/null 2>&1 && ok "namespace ${NAMESPACE} exists" || warn "namespace ${NAMESPACE} missing"
  if kubectl get nodes -o jsonpath='{.items[*].status.capacity.nvidia\.com/gpu}' 2>/dev/null | grep -qE '[1-9]'; then
    ok "GPUs are advertised on the cluster"
  else
    warn "no nvidia.com/gpu on any node — model pods will stay Pending (install NVIDIA GPU Operator on a real GPU cluster)"
  fi
}

case "${1:-all}" in
  crds)   install_crds ;;
  istio)  install_istio ;;
  ns)     install_ns ;;
  verify) verify ;;
  all)    install_crds; install_istio; install_ns; verify
          echo; ok "Bootstrap complete — now deploy with helm (see ../README.md §Deploy)";;
  *)      die "unknown arg '$1' (use: crds | istio | ns | verify | all)";;
esac
