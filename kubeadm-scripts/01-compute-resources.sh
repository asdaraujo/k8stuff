#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/defaults.sh

### VPC Networking

logmsg "Create the custom VPC network:"

gcloud compute networks create ${NETWORK} --subnet-mode custom

logmsg "Create the subnet in the VPC network:"

gcloud compute networks subnets create ${SUBNET} \
  --network ${NETWORK} \
  --range 10.240.0.0/24

### Firewall Rules

logmsg "Create a firewall rule that allows internal communication across all protocols:"

gcloud compute firewall-rules create ${FW_INTERNAL} \
  --allow tcp,udp,icmp \
  --network ${NETWORK} \
  --source-ranges 10.240.0.0/24,10.200.0.0/16

logmsg "Create a firewall rule that allows external SSH, ICMP, and HTTPS:"

gcloud compute firewall-rules create ${FW_EXTERNAL} \
  --allow tcp:22,tcp:6443,icmp \
  --network ${NETWORK} \
  --source-ranges 0.0.0.0/0

logmsg "List the firewall rules in the VPC network:"

gcloud compute firewall-rules list --filter="network:${NETWORK}"

### Kubernetes Public IP Address

logmsg "Allocate a static IP address that will be attached to the external load balancer fronting the Kubernetes API Servers:"

gcloud compute addresses create ${IP_ADDRESS} \
  --region ${REGION}

logmsg "Verify the static IP address was created in your default compute region:"

gcloud compute addresses list --filter="name=('${IP_ADDRESS}')"

### Kubernetes Controllers

logmsg "Create compute instances which will host the Kubernetes control plane:"

for instance in "${ALL_CONTROLLERS[@]}"; do
  logmsg "Creating $instance"
  gcloud compute instances create ${instance} \
    --async \
    --boot-disk-size 200GB \
    --can-ip-forward \
    --image-family ubuntu-2004-lts \
    --image-project ubuntu-os-cloud \
    --machine-type e2-standard-2 \
    --private-network-ip $(private_ip $instance) \
    --scopes compute-rw,storage-ro,service-management,service-control,logging-write,monitoring \
    --subnet ${SUBNET} \
    --tags ${NAMESPACE},controller \
    --labels "owner=${OWNER},enddate=${ENDDATE}"
done

### Kubernetes Workers

logmsg "Create compute instances which will host the Kubernetes worker nodes:"

for instance in "${ALL_WORKERS[@]}"; do
  logmsg "Creating $instance"
  gcloud compute instances create ${instance} \
    --async \
    --boot-disk-size 200GB \
    --can-ip-forward \
    --image-family ubuntu-2004-lts \
    --image-project ubuntu-os-cloud \
    --machine-type e2-standard-2 \
    --metadata pod-cidr=$(pod_cidr $instance) \
    --private-network-ip $(private_ip $instance) \
    --scopes compute-rw,storage-ro,service-management,service-control,logging-write,monitoring \
    --subnet ${SUBNET} \
    --tags ${NAMESPACE},worker
done

### Verification

logmsg "List the compute instances in your default compute zone:"

gcloud compute instances list --filter="tags.items=${NAMESPACE}"

