#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/defaults.sh

WORKER_JOIN_CMD=$(gcloud compute ssh ${ALL_CONTROLLERS[@]:0:1}  --ssh-key-file=${SSH_KEY_FILE} --command="kubeadm token create --print-join-command")
CERT_KEY=$(gcloud compute ssh ${ALL_CONTROLLERS[@]:0:1}  --ssh-key-file=${SSH_KEY_FILE} --command="sudo cat /etc/kubernetes/pki/certificate.key")
CONTROLLER_JOIN_CMD="$WORKER_JOIN_CMD --control-plane --certificate-key '$CERT_KEY'"
logmsg "Join command for workers:     $WORKER_JOIN_CMD"
logmsg "Join command for controllers: $CONTROLLER_JOIN_CMD"

CMD=$(cat <<CMDEOF
set -o errexit; set -o nounset; set -o pipefail
C_NORMAL="\$(echo -e "\033[0m")"; C_YELLOW="\$(echo -e "\033[33m")"
function logmsg() { local msg=\$1; echo "\${C_YELLOW}\${msg}\${C_NORMAL}"; }

logmsg "Join node \$(hostname -f) to the cluster"
sudo $WORKER_JOIN_CMD

CMDEOF
)

for instance in "${ALL_WORKERS[@]}"; do
  gcloud compute ssh ${instance} --ssh-key-file=${SSH_KEY_FILE} --command="$CMD" &
done

wait

CMD=$(cat <<CMDEOF
set -o errexit; set -o nounset; set -o pipefail
C_NORMAL="\$(echo -e "\033[0m")"; C_YELLOW="\$(echo -e "\033[33m")"
function logmsg() { local msg=\$1; echo "\${C_YELLOW}\${msg}\${C_NORMAL}"; }

logmsg "Join node \$(hostname -f) to the cluster control plane"
sudo $CONTROLLER_JOIN_CMD

CMDEOF
)

for instance in "${ALL_CONTROLLERS[@]:1}"; do
  gcloud compute ssh ${instance} --ssh-key-file=${SSH_KEY_FILE} --command="$CMD" &
done

wait

