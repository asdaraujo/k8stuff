#!/bin/bash
set -o errexit -o nounset -o pipefail
BASE_DIR=$(cd $(dirname $0); pwd -L)
source $BASE_DIR/defaults.sh

init_env

logmsg "Destroying previous cluster [$NAMESPACE]"

bash ./11-cleanup.sh

