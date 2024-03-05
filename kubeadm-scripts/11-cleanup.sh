#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/defaults.sh

logmsg "Delete the external load balancer network resources:"

INSTANCES=$(gcloud -q compute forwarding-rules list --filter=name:${NAMESPACE}- --format="value(name)")
if [[ ! -z ${INSTANCES} ]]; then
  gcloud -q compute forwarding-rules delete \
    ${INSTANCES} || true
fi

logmsg "Delete the target pool resources:"

INSTANCES=$(gcloud -q compute target-pools list --filter=name:${NAMESPACE}- --format="value(name)")
if [[ ! -z ${INSTANCES} ]]; then
  gcloud -q compute target-pools delete \
    ${INSTANCES} || true
fi

logmsg "Delete the HTTP health check resources:"

INSTANCES=$(gcloud -q compute http-health-checks list --filter=name:${NAMESPACE}- --format="value(name)")
if [[ ! -z ${INSTANCES} ]]; then
  gcloud -q compute http-health-checks delete \
    ${INSTANCES} || true
fi

logmsg "Delete the network routes:"

INSTANCES=$(gcloud -q compute routes list --filter=network:${NETWORK} --format=json | jq -r '.[] | select(.network != .nextHopNetwork).name')
if [[ ! -z ${INSTANCES} ]]; then
  gcloud -q compute routes delete \
    ${INSTANCES} || true
fi

logmsg "Delete the controller and worker compute instances:"

INSTANCES=$(gcloud -q compute instances list --filter=tags:${NAMESPACE} --format="value(name)")
if [[ ! -z ${INSTANCES} ]]; then
  gcloud -q compute instances delete \
    ${INSTANCES} \
    --zone ${ZONE} \
    --delete-disks=all || true
fi

logmsg "Delete the static ip address:"

INSTANCES=$(gcloud -q compute addresses list --filter=name:${IP_ADDRESS} --format="value(name)")
if [[ ! -z ${INSTANCES} ]]; then
  gcloud -q compute addresses delete ${INSTANCES} || true
fi

logmsg "Delete the firewall rules:"

INSTANCES=$(gcloud -q compute firewall-rules list --filter=network:${NETWORK} --format="value(name)")
if [[ ! -z ${INSTANCES} ]]; then
  gcloud -q compute firewall-rules delete \
    ${INSTANCES} || true
fi

logmsg "Delete the subnet:"

INSTANCES=$(gcloud -q compute networks subnets list --filter=network:${NETWORK} --format="value(name)")
if [[ ! -z ${INSTANCES} ]]; then
  gcloud -q compute networks subnets delete ${INSTANCES} || true
fi

logmsg "Delete the network VPC:"

INSTANCES=$(gcloud -q compute networks list --filter=name:${NETWORK} --format="value(name)")
if [[ ! -z ${INSTANCES} ]]; then
  gcloud -q compute networks delete ${INSTANCES} || true
fi
