# KV Events Enablement (PD Disaggregation)

This guide shows what to add, how to verify, and the expected impact when enabling vLLM KV events in a PD (Prefill/Decode) deployment.

## What to Add

Add the `--kv-events-config` flag to **both** prefill and decode containers in your modelservice values file.

Example (in `containers[0].args`):

```yaml
- "--kv-events-config"
- |-
  {
    "enable_kv_cache_events": true,
    "publisher": "zmq",
    "endpoint": "tcp://*:5557",
    "topic": "kv@$(POD_IP)@<MODEL_NAME>"
  }
```

Notes:
- `topic` should match your model name. Example: `Qwen/Qwen2.5-0.5B-Instruct` or `zai-org/glm-4.7-fp8`.
- This does **not** replace `--kv-transfer-config` (NixlConnector stays).

## How to Verify It’s Enabled

Check pod logs for the KV events config:

```bash
kubectl -n default logs -l llm-d.ai/role=prefill --tail 200 | grep -E "kv_events_config|enable_kv_cache_events|5557"
kubectl -n default logs -l llm-d.ai/role=decode  --tail 200 | grep -E "kv_events_config|enable_kv_cache_events|5557"
```

Expected log snippet (example):

```
kv_events_config: KVEventsConfig(enable_kv_cache_events=True, publisher='zmq', endpoint='tcp://*:5557', ...)
```

If you **do not** see `kv_events_config` at all, the flag was not applied.

## How to Observe Routing Impact

KV events only improve routing if the scheduler is configured to **consume** them (precise prefix-cache aware routing). If you only enable events in vLLM, you will **not** see routing changes yet.

You can check scheduler logs like this:

```bash
kubectl -n default logs -l inferencepool=gaie-pd-epp --all-containers=true --tail 200 | grep "Calculated score"
```

## Risk / Performance Impact

- **Low risk**: KV events are lightweight telemetry.
- **Possible tiny overhead** on vLLM from publishing events.
- No functional change unless the scheduler consumes these events.

## Summary

- Add `--kv-events-config` to prefill and decode.
- Confirm via logs that `kv_events_config` is present.
- Routing impact requires precise KV-events-aware scheduling.
