#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/defaults.sh

KUBERNETES_PUBLIC_ADDRESS=$(gcloud compute addresses describe ${IP_ADDRESS} \
  --region $REGION \
  --format 'value(address)')
echo "KUBERNETES_PUBLIC_ADDRESS: $KUBERNETES_PUBLIC_ADDRESS"

CMD=$(cat <<CMDEOF
set -o errexit; set -o nounset; set -o pipefail
C_NORMAL="\$(echo -e "\033[0m")"; C_YELLOW="\$(echo -e "\033[33m")"
function logmsg() { local msg=\$1; echo "\${C_YELLOW}\${msg}\${C_NORMAL}"; }

logmsg "Generate a certificate key"
sudo mkdir -p /etc/kubernetes/pki
sudo bash -c "umask 0077; sudo kubeadm certs certificate-key | tee /etc/kubernetes/pki/certificate.key"

logmsg "Load kernel modules"

IPADDR=\$(curl -s ifconfig.me)
NODENAME=\$(hostname -s)
POD_CIDR="192.168.0.0/16"

cat > kubeadm-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  name: \$NODENAME
  ignorePreflightErrors:
    - Swap
certificateKey: "\$(sudo cat /etc/kubernetes/pki/certificate.key)"
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
apiServer:
  certSANs:
    - "\$IPADDR"
    - "$KUBERNETES_PUBLIC_ADDRESS"
controlPlaneEndpoint: "\$IPADDR"
kubernetesVersion: 1.29.0
networking:
  podSubnet: "\$POD_CIDR"
---
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
cgroupDriver: systemd
EOF

logmsg "Initialize kubeadm"
sudo kubeadm init --config kubeadm-config.yaml --upload-certs

logmsg "Copy kubeconfig to my homedir"
mkdir -p \$HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config
sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config

logmsg "Install Calico Network Plugin for Pod Networking"
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml
curl https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml -O
kubectl create -f custom-resources.yaml

logmsg "Print join command"
kubeadm token create --print-join-command

CMDEOF
)

for instance in "${ALL_CONTROLLERS[@]:0:1}"; do
  gcloud compute ssh ${instance} --ssh-key-file=${SSH_KEY_FILE} --command="$CMD" &
done

wait

