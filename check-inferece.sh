ROUTE_NS=llm-d
ROUTE_NAME=llm-d-pd-disaggregation

echo "=== HTTPRoute ==="
kubectl get httproute -n "$ROUTE_NS" "$ROUTE_NAME" -o yaml | sed -n '1,220p'

echo
echo "=== Route Conditions ==="
kubectl get httproute -n "$ROUTE_NS" "$ROUTE_NAME" \
  -o jsonpath='{range .status.parents[*].conditions[*]}{.type}{"="}{.status}{" reason="}{.reason}{" message="}{.message}{"\n"}{end}'

echo
echo "=== BackendRefs ==="
kubectl get httproute -n "$ROUTE_NS" "$ROUTE_NAME" \
  -o jsonpath='{range .spec.rules[*].backendRefs[*]}{.group}{"|"}{.kind}{"|"}{.name}{"|"}{.namespace}{"\n"}{end}' \
| while IFS='|' read -r GROUP KIND NAME NS; do
    [ -z "$NS" ] && NS="$ROUTE_NS"
    echo "backendRef -> group=$GROUP kind=$KIND name=$NAME namespace=$NS"

    echo "--- Exists?"
    kubectl get "$KIND" -n "$NS" "$NAME" -o name 2>&1 || true

    if [ "$KIND" = "InferencePool" ]; then
      echo "--- InferencePool Conditions"
      kubectl get inferencepool -n "$NS" "$NAME" \
        -o jsonpath='{range .status.parents[*].conditions[*]}{.type}{"="}{.status}{" reason="}{.reason}{" message="}{.message}{"\n"}{end}' 2>/dev/null || true

      echo "--- InferencePool Selector"
      kubectl get inferencepool -n "$NS" "$NAME" \
        -o jsonpath='{range .spec.selector.matchLabels[*]}{""}{end}' >/dev/null 2>&1

      APP=$(kubectl get inferencepool -n "$NS" "$NAME" -o jsonpath='{.spec.selector.matchLabels.app}' 2>/dev/null)
      GUIDE=$(kubectl get inferencepool -n "$NS" "$NAME" -o jsonpath='{.spec.selector.matchLabels.llm-d\.ai/guide}' 2>/dev/null)
      SERVING=$(kubectl get inferencepool -n "$NS" "$NAME" -o jsonpath='{.spec.selector.matchLabels.llm-d\.ai/inference-serving}' 2>/dev/null)
      MODEL=$(kubectl get inferencepool -n "$NS" "$NAME" -o jsonpath='{.spec.selector.matchLabels.llm-d\.ai/model}' 2>/dev/null)

      echo "app=$APP"
      echo "guide=$GUIDE"
      echo "inference-serving=$SERVING"
      echo "model=$MODEL"

      echo "--- Matching Pods"
      kubectl get pods -n "$NS" \
        -l "app=$APP,llm-d.ai/guide=$GUIDE,llm-d.ai/inference-serving=$SERVING,llm-d.ai/model=$MODEL" \
        -L llm-d.ai/role -o wide 2>&1 || true

      echo "--- EndpointPickerRef"
      kubectl get inferencepool -n "$NS" "$NAME" \
        -o jsonpath='kind={.spec.endpointPickerRef.kind} name={.spec.endpointPickerRef.name} port={.spec.endpointPickerRef.port.number}{"\n"}' 2>/dev/null || true
    fi

    echo
  done
