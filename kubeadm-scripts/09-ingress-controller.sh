#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/defaults.sh

logmsg "Install nginx ingress controller"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/baremetal/deploy.yaml

logmsg "Install cert-manager"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.3/cert-manager.yaml

logmsg "Install Metric Server with the --kubelet-insecure-tls=true option"
kubectl apply -f <(curl -s -L https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml | sed -E 's/^( *- )(--metric-resolution)/\1--kubelet-insecure-tls=true\n\1\2/')
