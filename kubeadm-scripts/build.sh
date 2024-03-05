#!/bin/bash
set -o errexit -o nounset -o pipefail
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/defaults.sh

init_env

trap 'RET=$?; echo "Something went wrong... Try again."' 0

logmsg "Destroying previous cluster [$NAMESPACE]"

bash ./11-cleanup.sh

logmsg "Building cluster [$NAMESPACE]"

bash ./01-compute-resources.sh
sleep 10
bash ./02-test-access.sh
bash ./03-prepare-hosts.sh
bash ./04-initialize-kubeadm.sh
bash ./05-join-nodes.sh
bash ./06-kubeconfig.sh
bash ./07-load-balancer.sh
bash ./08-longhorn.sh
bash ./09-ingress-controller.sh

trap - 0
echo "Cluster successfully deployed."
