#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-cicd-demo}"
APP="${APP:-demo-web}"
ARGO_APP="${ARGO_APP:-k8s-argo-jenkins-test01}"

echo "== [1] Kubernetes Nodes =="
kubectl get nodes -o wide

echo
echo "== [2] Argo CD Pods =="
kubectl get pods -n argocd -o wide

echo
echo "== [3] Jenkins Pods =="
kubectl get pods -n jenkins -o wide

echo
echo "== [4] Argo CD Application =="
if kubectl get application "$ARGO_APP" -n argocd >/dev/null 2>&1; then
  kubectl get application "$ARGO_APP" -n argocd
else
  echo "WARN: Argo CD Application '$ARGO_APP' is not created yet."
fi

echo
echo "== [5] Demo Workloads =="
if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  kubectl get all -n "$NAMESPACE"
  echo
  kubectl get pods -n "$NAMESPACE" -o wide
else
  echo "WARN: Namespace '$NAMESPACE' does not exist yet."
  exit 0
fi

echo
echo "== [6] Deployment Image =="
kubectl get deployment "$APP" -n "$NAMESPACE" \
  -o jsonpath='{.spec.template.spec.containers[0].image}'; echo

echo
echo "== [7] Rollout Status =="
kubectl rollout status deployment/"$APP" -n "$NAMESPACE" --timeout=60s

echo
echo "== [8] Service / External IP =="
kubectl get svc "$APP" -n "$NAMESPACE" -o wide
VIP=$(kubectl get svc "$APP" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)

if [[ -n "$VIP" ]]; then
  echo "MetalLB VIP: $VIP"
  echo "Test URL: http://$VIP/"
  echo "Smoke URL: http://$VIP/status.html"
else
  echo "WARN: LoadBalancer External IP is not allocated yet. Check MetalLB."
fi

echo
echo "Verification completed."
