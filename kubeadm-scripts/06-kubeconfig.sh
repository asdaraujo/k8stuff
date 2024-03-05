#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/defaults.sh

TMP_KUBECONFIG=.kubeconfig.${NAMESPACE}

gcloud compute ssh ${ALL_CONTROLLERS[@]:0:1}  --ssh-key-file=${SSH_KEY_FILE} --command="sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf config view --flatten --raw=true" > $TMP_KUBECONFIG

kubectl --kubeconfig=$TMP_KUBECONFIG config view --raw=true -o json | jq '."current-context" = "'"${NAMESPACE}"'" | .clusters[0].name = "'"${NAMESPACE}"'-cluster" | .users[0].name = "'"${NAMESPACE}"'-user" | .contexts[0].name = "'"${NAMESPACE}"'" | .contexts[0].context.cluster = "'"${NAMESPACE}"'-cluster" | .contexts[0].context.user = "'"${NAMESPACE}"'-user"' > .kc.tmp
kubectl --kubeconfig=.kc.tmp config view --raw=true > $TMP_KUBECONFIG
rm -f .kc.tmp

KUBECONFIG_BACKUP=$HOME/.kube/config.backup.$(date +%Y%m%d%H%M%S)
cp $HOME/.kube/config $KUBECONFIG_BACKUP && \
KUBECONFIG=$TMP_KUBECONFIG:$KUBECONFIG_BACKUP kubectl config view --raw=true --merge=true > $HOME/.kube/config

#rm -f $TMP_KUBECONFIG
