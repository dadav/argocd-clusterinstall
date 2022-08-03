#!/bin/bash

ns=argocd

k3d cluster create argocd --api-port 6443 -p 8080:80@loadbalancer --agents 2

kubectl create ns $ns
kubectl -n $ns create -f https://raw.githubusercontent.com/argoproj/argo-cd/master/manifests/install.yaml
kubectl -n $ns patch cm argocd-cmd-params-cm -p '{"data":{"server.insecure":"true"}}'
kubectl -n $ns patch cm argocd-cmd-params-cm -p '{"data":{"server.rootpath":"/argocd"}}'
cat <<EOF | kubectl -n $ns create -f -
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
kubectl -n $ns wait --for=condition=Ready pods --all

echo "open: http://localhost:8080/argocd/"
echo "username: admin"
echo -n "password: "
kubectl -n $ns get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
