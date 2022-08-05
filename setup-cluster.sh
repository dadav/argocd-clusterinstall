#!/bin/bash

ns="argocd"
port="8080"

if command -v gum &>/dev/null; then
  # use fancy gum
  old_ns="$ns"
  ns="$(gum input --prompt "Namespace> " --placeholder "What should argocd's namespace be?" <<<$ns)"
  if [[ "$ns" != "$old_ns" ]]; then
    # update the namespace in the kustomize file
    sed -i "s@\(namespace:\) .*@\1 $ns@g" argocd-resources/kustomize.yaml
  fi

  port="$(gum input --prompt "Port> " --placeholder "Which port should be forwarded?" <<<$port)"
  if ! systemctl is-active docker.service &>/dev/null; then
    if gum confirm "Should docker be started with sudo now?"; then
      sudo systemctl start docker.service
    else
      exit 1
    fi
  fi
else
  if ! systemctl is-active docker.service &>/dev/null; then
    echo "Docker is not running"
    exit 1
  fi
fi

# shellcheck disable=SC2090
k3d cluster create argocd --api-port 6443 -p "$port":80@loadbalancer --agents 2

kubectl create ns "$ns"
kubectl -n "$ns" create -f https://raw.githubusercontent.com/argoproj/argo-cd/master/manifests/install.yaml
kubectl -n "$ns" patch cm argocd-cmd-params-cm -p '{"data":{"server.insecure":"true"}}'
kubectl -n "$ns" patch cm argocd-cmd-params-cm -p '{"data":{"server.rootpath":"/argocd"}}'
cat <<EOF | kubectl -n "$ns" create -f -
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx
  annotations:
    ingress.kubernetes.io/ssl-redirect: "false"
spec:
  rules:
  - http:
      paths:
      - path: /argocd
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
EOF

echo "Waiting for pods to be ready..."
# shellcheck disable=SC2090
kubectl -n "$ns" wait --for=condition=Ready pods --all

echo "open: http://localhost:$port/argocd/"
echo "username: admin"
echo -n "password: "
kubectl -n "$ns" get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
