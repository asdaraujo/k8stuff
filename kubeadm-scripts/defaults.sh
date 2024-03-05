# Set defaults below

# BEGIN DO NOT CHANGE
CONFIG_FILE=$BASE_DIR/.build.config
if [[ -f $CONFIG_FILE ]]; then
  source $CONFIG_FILE
fi
# END DO NOT CHANGE

OWNER=${OWNER:-drwho}
# ENDDATE is 7 days from today
ENDDATE=${ENDDATE:-$(python -c 'from datetime import datetime as dt, timedelta as td; print((dt.now() + td(days=7)).strftime("%m%d%Y"))')}
SSH_KEY_FILE=${SSH_KEY_FILE:-~/.ssh/id_rsa}

NUM_CONTROLLERS=${NUM_CONTROLLERS:-2}  # Max: 9 nodes
NUM_WORKERS=${NUM_WORKERS:-5}  # Max: 9 nodes
NAMESPACE=${NAMESPACE:-example}
NETWORK=${NAMESPACE}-vpc
SUBNET=${NAMESPACE}-subnet
FW_INTERNAL=${NAMESPACE}-allow-internal
FW_EXTERNAL=${NAMESPACE}-allow-external
FW_HEALTHCHECK=${NAMESPACE}-allow-health-check
FW_NGINX=${NAMESPACE}-allow-nginx-service
IP_ADDRESS=${NAMESPACE}-ip-address
CONTROLLER_PREFIX=${NAMESPACE}-controller
WORKER_PREFIX=${NAMESPACE}-worker
HEALTH_CHECK=${NAMESPACE}-k8s-health-check
TARGET_POOL=${NAMESPACE}-target-pool
FWD_RULE=${NAMESPACE}-forwarding-rule

# Don't change below this line

if [[ ${0:-defaults.sh} != "defaults.sh" && ${0:-bash} != "bash" ]]; then
  set -o errexit
  set -o nounset
  set -o pipefail
fi

# Avoid setting using array index to it's compatible with Bash and Zsh
ALL_CONTROLLERS=()
for (( i=0; i<$NUM_CONTROLLERS; i++ )); do
  if [[ $i -eq 0 ]]; then
    ALL_CONTROLLERS=(${CONTROLLER_PREFIX}-$i)
  else
    ALL_CONTROLLERS=("${ALL_CONTROLLERS[@]:-}" ${CONTROLLER_PREFIX}-$i)
  fi
done
ALL_WORKERS=()
for (( i=0; i<$NUM_WORKERS; i++ )); do
  if [[ $i -eq 0 ]]; then
    ALL_WORKERS=(${WORKER_PREFIX}-$i)
  else
    ALL_WORKERS=("${ALL_WORKERS[@]:-}" ${WORKER_PREFIX}-$i)
  fi
done

REGION=$(gcloud config get-value compute/region)
ZONE=$(gcloud config get-value compute/zone)

export KUBECONFIG=./.kubeconfig:~/.kube/config

function logmsg() {
  local msg=$1
  echo "${C_YELLOW}${msg}${C_NORMAL}"
}

C_NORMAL="$(echo -e "\033[0m")"
C_BOLD="$(echo -e "\033[1m")"
C_DIM="$(echo -e "\033[2m")"
C_BLACK="$(echo -e "\033[30m")"
C_RED="$(echo -e "\033[31m")"
C_GREEN="$(echo -e "\033[32m")"
C_YELLOW="$(echo -e "\033[33m")"
C_BLUE="$(echo -e "\033[34m")"
C_WHITE="$(echo -e "\033[97m")"
C_BG_GREEN="$(echo -e "\033[42m")"
C_BG_RED="$(echo -e "\033[101m")"
C_BG_MAGENTA="$(echo -e "\033[105m")"

function private_ip() {
  local hostname=$1
  if [[ $hostname == "$WORKER_PREFIX"* ]]; then
    echo "10.240.0.2${hostname##*-}"
  elif [[ $hostname == "$CONTROLLER_PREFIX"* ]]; then
    echo "10.240.0.1${hostname##*-}"
  else
    echo "ERROR: Unknown hostname $hostname"
    exit 1
  fi
}

function pod_cidr() {
  local hostname=$1
  if [[ $hostname == "$WORKER_PREFIX"* ]]; then
    echo "10.200.${hostname##*-}.0/24"
  elif [[ $hostname == "$CONTROLLER_PREFIX"* ]]; then
    echo "ERROR: Function undefined for controllers"
    exit 1
  else
    echo "ERROR: Unknown hostname $hostname"
    exit 1
  fi
}

function init_env() {
  # Check gcloud login
  GUSER=$(gcloud auth list --format=json | jq -r '.[] | select(.status == "ACTIVE").account')
  RET=$?
  if [[ $RET -ne 0 || $GUSER == "" ]]; then
    echo 'ERROR: Ensure that gcloud CLI is installed, configured and that you have successfully logged in with "gcloud auth login".'
    exit
  else
    echo "Using gcloud session for user: $GUSER."
    export OWNER=${GUSER%@*}
  fi
  
  # Checking region:
  REGION=$(gcloud config get compute/region)
  ZONE=$(gcloud config get compute/zone)
  echo "The cluster will be built in the following location:"
  echo "  Region: $REGION"
  echo "  Zone:   $ZONE"
  echo -n "Do you want to continue? (Y/n) "
  read CONFIRM
  if [[ $CONFIRM != "" && $(echo $CONFIRM | tr "A-Z" "a-z") != "y" ]]; then
    echo "If you want to change the region/zone, please execute the following commands:"
    echo "  List zones and regions: gcloud compute zones list"
    echo "  Set default region:     gcloud config set compute/region <region_name>"
    echo "  Set default zone:       gcloud config set compute/zone <zone_name>"
    exit 0
  fi
  
  echo -n "Namespace [${NAMESPACE:-}]: "
  read NS
  NAMESPACE=${NS:-$NAMESPACE}
  if [[ $NAMESPACE == "" ]]; then
    echo "ERROR: You must specify a namespace."
    exit 0
  fi

  if [[ ! -s $SSH_KEY_FILE || $(grep -c "PRIVATE KEY" "$SSH_KEY_FILE") -eq 0 ]]; then
    echo -n "Specify a valid SSH private key file []: "
    read FILE
    SSH_KEY_FILE=${FILE:-$SSH_KEY_FILE}
    # Force globbing
    eval SSH_KEY_FILE=$SSH_KEY_FILE
    if [[ ! -s $SSH_KEY_FILE || $(grep -c "PRIVATE KEY" "$SSH_KEY_FILE") -eq 0 ]]; then
      echo "ERROR: File $SSH_KEY_FILE is not a valid SSH private key file."
      exit 1
    fi
  fi

  cat > $CONFIG_FILE <<EOF
export NAMESPACE=$NAMESPACE
export SSH_KEY_FILE=$SSH_KEY_FILE
EOF
  export NAMESPACE
  export SSH_KEY_FILE
}
