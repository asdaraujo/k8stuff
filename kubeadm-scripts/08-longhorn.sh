#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/defaults.sh

CMD=$(cat <<CMDEOF
set -o errexit; set -o nounset; set -o pipefail
C_NORMAL="\$(echo -e "\033[0m")"; C_YELLOW="\$(echo -e "\033[33m")"
function logmsg() { local msg=\$1; echo "\${C_YELLOW}\${msg}\${C_NORMAL}"; }

logmsg "Install helm"
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
sudo bash ./get_helm.sh

logmsg "Install longhorn"
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm repo update
helm install longhorn longhorn/longhorn --namespace longhorn-system --create-namespace --version 1.5.3

CMDEOF
)

for instance in "${ALL_CONTROLLERS[@]:0:1}"; do
  gcloud compute ssh ${instance} --ssh-key-file=${SSH_KEY_FILE} --command="$CMD" &
done

wait

