#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/defaults.sh

CMD=$(cat <<CMDEOF
set -o errexit; set -o nounset; set -o pipefail
C_NORMAL="\$(echo -e "\033[0m")"; C_YELLOW="\$(echo -e "\033[33m")"
function logmsg() { local msg=\$1; echo "\${C_YELLOW}\${msg}\${C_NORMAL}"; }

logmsg "Load kernel modules"

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

logmsg "sysctl params required by setup, params persist across reboots"
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

logmsg "Disable swap"
sudo swapoff -a

logmsg "Apply sysctl params without reboot"
sudo sysctl --system

logmsg "Verify that the br_netfilter, overlay modules are loaded"
lsmod | grep br_netfilter
lsmod | grep overlay

logmsg "Verify that the net.bridge.bridge-nf-call-iptables, net.bridge.bridge-nf-call-ip6tables, and"
logmsg "net.ipv4.ip_forward system variables are set to 1 in your sysctl config by running the following command:"
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward

logmsg "Installing containerd"
wget https://github.com/containerd/containerd/releases/download/v1.7.11/containerd-1.7.11-linux-amd64.tar.gz
sudo tar -C /usr/local -xzvf containerd-1.7.11-linux-amd64.tar.gz
sudo mkdir -p /usr/local/lib/systemd/system/
curl https://raw.githubusercontent.com/containerd/containerd/main/containerd.service | sudo tee /usr/local/lib/systemd/system/containerd.service
sudo systemctl daemon-reload
sudo systemctl enable --now containerd

logmsg "Installing runc"
wget https://github.com/opencontainers/runc/releases/download/v1.1.11/runc.amd64
sudo install -m 755 runc.amd64 /usr/local/sbin/runc

logmsg "Installing CNI plugins"
wget https://github.com/containernetworking/plugins/releases/download/v1.4.0/cni-plugins-linux-amd64-v1.4.0.tgz
sudo mkdir -p /opt/cni/bin
sudo tar -C /opt/cni/bin -xzvf  cni-plugins-linux-amd64-v1.4.0.tgz

logmsg "Configure and start containerd"
sudo mkdir -p /etc/containerd/
/usr/local/bin/containerd config default | sed 's/SystemdCgroup =.*/SystemdCgroup = true/' | sudo tee /etc/containerd/config.toml
sudo systemctl restart containerd
/usr/local/bin/containerd config dump | egrep -i "systemd.*cgroup"

logmsg "Update the apt package index and install packages needed to use the Kubernetes apt repository:"

sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

logmsg "Download the public signing key for the Kubernetes package repositories. The same signing key is used for all repositories so you can disregard the version in the URL:"

sudo mkdir -p /etc/apt/keyrings/
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

logmsg "Overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list"
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

logmsg "Update the apt package index, install kubelet, kubeadm and kubectl, and pin their version:"

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

logmsg "Add the node IP to KUBELET_EXTRA_ARGS."

sudo apt-get install -y jq
local_ip="\$(ip --json a s | jq -r '.[] | if .ifname == "ens4" then .addr_info[] | if .family == "inet" then .local else empty end else empty end')"
sudo tee /etc/default/kubelet << EOF
KUBELET_EXTRA_ARGS=--node-ip=\$local_ip
EOF
cat /etc/default/kubelet

CMDEOF
)

for instance in "${ALL_CONTROLLERS[@]}" "${ALL_WORKERS[@]}"; do
  gcloud compute ssh ${instance} --ssh-key-file=${SSH_KEY_FILE} --command="$CMD" &
done

wait

