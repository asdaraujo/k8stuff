#!/bin/bash
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/defaults.sh

### Verification

logmsg "List the compute instances in your default compute zone:"

gcloud compute instances list --filter="tags.items=${NAMESPACE}"

### Configuring SSH Access

logmsg "Test SSH access to the compute instances:"

for instance in "${ALL_CONTROLLERS[@]}" "${ALL_WORKERS[@]}"; do
  gcloud compute ssh ${instance} --ssh-key-file=${SSH_KEY_FILE} --command="hostname"
done
