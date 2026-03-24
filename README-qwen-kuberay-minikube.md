# Qwen on KubeRay on Minikube

This guide explains how to deploy `Qwen/Qwen2.5-0.5B-Instruct` on Kubernetes with KubeRay, in a dedicated namespace, using the `production-stack` Helm chart.

The goal is to get a real `RayCluster` and expose the model through the vLLM engine service.

## What this guide deploys

- A dedicated namespace: `qwen-kuberay-demo`
- A KubeRay operator in `kuberay-system`
- A Ray head pod
- A Ray worker pod
- A vLLM engine service
- A Qwen model served through KubeRay

## Important note before you start

Do not use `ghcr.io/llm-d/llm-d-cpu:v0.5.0` for the KubeRay deployment.

That image works for the `pd-cpu` demo, but it does not include the `ray` binary, so the Ray head pod fails with:

```text
ray: command not found
```

For the KubeRay flow, use an image that contains both:

- `vllm`
- `ray`

The values file prepared for this guide is:

`/home/etty/production-stack/tutorials/assets/values-15-qwen-kuberay-minikube.yaml`

## Prerequisites

Install these tools on the host:

- Docker
- `kubectl`
- `helm`
- `minikube`

Verify:

```bash
docker --version
kubectl version --client
helm version
minikube version
```

## Resource requirements

Recommended minimum for this demo:

- 8 vCPU
- 12 GiB RAM
- 40-60 GiB free disk for Minikube and images

Before deploying, verify that the host is not full:

```bash
df -h /
```

If `/` is close to `100%`, KubeRay pods may get stuck in:

```text
ContainerCreating
FailedCreatePodSandBox
operation timeout: context deadline exceeded
```

## Step 1: Start Minikube

Start a fresh Minikube with enough resources:

```bash
minikube start \
  --driver=docker \
  --cpus=8 \
  --memory=12288 \
  --disk-size=60g
```

Verify:

```bash
kubectl config current-context
kubectl get nodes
```

Expected current context:

```text
minikube
```

## Step 2: Install KubeRay

Add the Helm repo and install the operator:

```bash
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm repo update

helm upgrade --install kuberay-operator kuberay/kuberay-operator \
  --version 1.2.0 \
  -n kuberay-system \
  --create-namespace
```

Wait until it is ready:

```bash
kubectl wait --for=condition=Available deployment/kuberay-operator \
  -n kuberay-system \
  --timeout=180s
```

Verify:

```bash
kubectl get pods -n kuberay-system
kubectl get crd | grep ray.io
```

## Step 3: Prepare the namespace and Hugging Face token

Create a dedicated namespace:

```bash
kubectl create namespace qwen-kuberay-demo
```

Export your Hugging Face token:

```bash
export HF_TOKEN='hf_xxx'
```

Create the secret used by the values file:

```bash
kubectl -n qwen-kuberay-demo create secret generic hf-token \
  --from-literal=token="$HF_TOKEN"
```

## Step 4: Review the values file

This guide uses:

`/home/etty/production-stack/tutorials/assets/values-15-qwen-kuberay-minikube.yaml`

Current intent of that file:

- model: `Qwen/Qwen2.5-0.5B-Instruct`
- one Ray head
- one Ray worker
- router disabled to reduce memory footprint
- CPU-oriented env vars like `VLLM_TARGET_DEVICE=cpu`

Review it:

```bash
sed -n '1,220p' /home/etty/production-stack/tutorials/assets/values-15-qwen-kuberay-minikube.yaml
```

## Step 5: Install the Helm release

Deploy the stack:

```bash
helm install qwen-kuberay /home/etty/production-stack/helm \
  -n qwen-kuberay-demo \
  -f /home/etty/production-stack/tutorials/assets/values-15-qwen-kuberay-minikube.yaml
```

To upgrade after changes:

```bash
helm upgrade qwen-kuberay /home/etty/production-stack/helm \
  -n qwen-kuberay-demo \
  -f /home/etty/production-stack/tutorials/assets/values-15-qwen-kuberay-minikube.yaml
```

## Step 6: Watch the deployment

```bash
kubectl get pods -n qwen-kuberay-demo -w
kubectl get raycluster -n qwen-kuberay-demo -o wide
kubectl get all -n qwen-kuberay-demo
```

Expected objects:

- one head pod
- one worker pod
- one `RayCluster`
- one engine service

## Step 7: Verify that the model is exposed

The service created by the chart is:

```text
qwen-kuberay-qwen25-cpu-raycluster-engine-service
```

Port-forward it:

```bash
kubectl port-forward -n qwen-kuberay-demo \
  svc/qwen-kuberay-qwen25-cpu-raycluster-engine-service \
  30080:80
```

In another shell:

```bash
curl http://127.0.0.1:30080/v1/models
```

Then run a completion test:

```bash
curl -X POST http://127.0.0.1:30080/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-0.5B-Instruct",
    "prompt": "Explain in one sentence what Ray is.",
    "max_tokens": 32
  }'
```

If everything works, you now have:

- KubeRay installed
- a dedicated namespace
- a Ray-based deployment
- Qwen served through vLLM

## Useful debug commands

```bash
kubectl get pods -n qwen-kuberay-demo -o wide
kubectl get events -n qwen-kuberay-demo --sort-by=.lastTimestamp
kubectl describe node minikube | sed -n '/Allocated resources:/,/Events:/p'
kubectl logs -n qwen-kuberay-demo $(kubectl get pods -n qwen-kuberay-demo -o name | grep head)
```

## Troubleshooting

### `ray: command not found`

Cause:

- wrong image for KubeRay

Fix:

- do not use `ghcr.io/llm-d/llm-d-cpu:v0.5.0`
- use an image that includes `ray`

### `FailedCreatePodSandBox`

Cause:

- host disk is full

Check:

```bash
df -h /
```

### `Insufficient memory`

Cause:

- Minikube does not have enough RAM for the head and worker

Fix:

- restart Minikube with more memory
- or reduce `requestMemory` in the values file

## Cleanup

```bash
helm uninstall qwen-kuberay -n qwen-kuberay-demo
kubectl delete namespace qwen-kuberay-demo

helm uninstall kuberay-operator -n kuberay-system
kubectl delete namespace kuberay-system
```
