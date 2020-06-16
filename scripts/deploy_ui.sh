#!/usr/bin/env bash
set -euo pipefail

source scripts/utils.sh

export ACTION=${ACTION:-full}
export NODE_IP=$(get_main_ip)
export UI_PORT=${UI_PORT:-6008}
export KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}
export CONTAINER_COMMAND=${CONTAINER_COMMAND:-podman}
export UI_DEPLOY_FILE=build/ui_deploy.yaml
export UI_SERVICE_NAME=ocp-metal-ui
export UI_IMAGE=${UI_IMAGE:-quay.io/ocpmetal/ocp-metal-ui:latest}
export NAMESPACE=assisted-installer

if [ ${ACTION} = redeploy ] ; then
  print_log "Restarting ui"
  kubectl --kubeconfig=${KUBECONFIG} rollout restart deployment/${UI_SERVICE_NAME} -n ${NAMESPACE}
else
  if kubectl --kubeconfig=${KUBECONFIG} get deployment/${UI_SERVICE_NAME} -n assisted-installer 2>&1 > /dev/null ; then
    print_log "Existing UI deployment found. Consider setting:"
    print_log "  ACTION=redeploy $0"
  fi

  mkdir -p build

  print_log "Starting ui"
  ${CONTAINER_COMMAND} run --pull=always --rm ${UI_IMAGE} /deploy/deploy_config.sh -i ${UI_IMAGE} > ${UI_DEPLOY_FILE}
  kubectl --kubeconfig=${KUBECONFIG} apply -f ${UI_DEPLOY_FILE}
fi

print_log "Config firewall"
sudo systemctl start firewalld
sudo firewall-cmd --zone=public --permanent --add-port=${UI_PORT}/tcp
sudo firewall-cmd --reload

print_log "Wait till ui api is ready"
wait_for_url_and_run "$(minikube service ${UI_SERVICE_NAME} --url -n ${NAMESPACE})" "echo \"waiting for ${UI_SERVICE_NAME}\""

print_log "Starting port forwarding for deployment/${UI_SERVICE_NAME}"

wait_for_url_and_run "http://${NODE_IP}:${UI_PORT}" "spawn_port_forwarding_command ${UI_SERVICE_NAME} ${UI_PORT}"

print_log "OCP METAL UI can be reached at http://${NODE_IP}:${UI_PORT}"
print_log "Done"

