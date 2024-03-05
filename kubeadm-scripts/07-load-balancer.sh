#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/defaults.sh

KUBERNETES_PUBLIC_ADDRESS=$(gcloud compute addresses describe ${IP_ADDRESS} \
  --region $REGION \
  --format 'value(address)')
echo "KUBERNETES_PUBLIC_ADDRESS: $KUBERNETES_PUBLIC_ADDRESS"

## The Kubernetes Frontend Load Balancer

CMD=$(cat <<CMDEOF
set -o errexit; set -o nounset; set -o pipefail
C_NORMAL="\$(echo -e "\033[0m")"; C_YELLOW="\$(echo -e "\033[33m")"
function logmsg() { local msg=\$1; echo "\${C_YELLOW}\${msg}\${C_NORMAL}"; }

logmsg "Install a basic web server to handle HTTP health checks: \$(hostname -s)"

if [[ ! -f /usr/sbin/nginx ]]; then
  sudo apt-get update
  sudo apt-get install -y nginx
fi

cat <<EOF | sudo tee /etc/nginx/sites-available/kubernetes.default.svc.cluster.local
server {
  listen      80;
  server_name kubernetes.default.svc.cluster.local;

  location /healthz {
     proxy_pass                    https://127.0.0.1:6443/healthz;
     proxy_ssl_trusted_certificate /var/lib/kubernetes/ca.pem;
  }
}
EOF

sudo rm -f /etc/nginx/sites-enabled/kubernetes.default.svc.cluster.local
sudo ln -s /etc/nginx/sites-available/kubernetes.default.svc.cluster.local /etc/nginx/sites-enabled/kubernetes.default.svc.cluster.local

sudo systemctl enable nginx
sudo systemctl restart nginx

logmsg "Verification: \$(hostname -s)"

kubectl cluster-info

logmsg "Test the nginx HTTP health check proxy: \$(hostname -s)"

curl -s -H "Host: kubernetes.default.svc.cluster.local" -i http://127.0.0.1/healthz; echo
[[ \$(curl -s -H "Host: kubernetes.default.svc.cluster.local" -i http://127.0.0.1/healthz | grep -i ok | wc -l) -eq 2 ]]

CMDEOF
)

for instance in "${ALL_CONTROLLERS[@]}"; do
  gcloud compute ssh ${instance} --ssh-key-file=${SSH_KEY_FILE} --command="$CMD" &
done

wait

logmsg "Create the health check for the external load balancer:"

gcloud compute http-health-checks create ${HEALTH_CHECK} \
  --description "Kubernetes Health Check" \
  --host "kubernetes.default.svc.cluster.local" \
  --request-path "/healthz"

logmsg "Create firewall rule for the external load balancer:"

gcloud compute firewall-rules create ${FW_HEALTHCHECK} \
  --network ${NETWORK} \
  --source-ranges 209.85.152.0/22,209.85.204.0/22,35.191.0.0/16 \
  --allow tcp

gcloud compute firewall-rules create ${NAMESPACE}-external-access-from-within \
  --allow tcp,udp,icmp \
  --network ${NETWORK} \
  --source-ranges $(gcloud -q compute instances list --filter=name:${NAMESPACE} --format=json | jq -r '.[].networkInterfaces[].accessConfigs[].natIP | "\(.)/32"' | tr "\n" "," | sed 's/,$//')

logmsg "Create target pool for the external load balancer:"

gcloud compute target-pools create ${TARGET_POOL} \
  --http-health-check ${HEALTH_CHECK} \
  --region ${REGION}

logmsg "Add backend instances to the target pool:"

# TODO: Once additional controllers are added to the cluster, ensure all of them are added to the backend below
gcloud compute target-pools add-instances ${TARGET_POOL} \
 --instances $(IFS=,; set -- "${ALL_CONTROLLERS[@]:0:1}"; echo "$*") \
 --instances-zone ${ZONE}

logmsg "Create forwarding rules:"

gcloud compute forwarding-rules create ${FWD_RULE} \
  --address ${KUBERNETES_PUBLIC_ADDRESS} \
  --ports 6443 \
  --region ${REGION} \
  --target-pool ${TARGET_POOL}

logmsg "Verification:"

logmsg "Make a HTTP request for the Kubernetes version info:"

gcloud compute scp --ssh-key-file=${SSH_KEY_FILE} ${ALL_CONTROLLERS[@]:0:1}:/etc/kubernetes/pki/ca.crt ./ca.crt
set +e
retries=30
while true; do
  if [[ $( (curl -i -s -w "\nHTTP code: %{http_code}\n" --cacert ./ca.crt "https://${KUBERNETES_PUBLIC_ADDRESS}:6443/version" | tee >(cat >&2)) | grep -c "HTTP code: 200" ) -eq 1 ]]; then
    break
  else
    retries=$((retries - 1))
    if [[ $retries -gt 0 ]]; then
      sleep 10
    else
      echo "Failed to verify load balancer."
      exit 1
    fi
  fi
done


