#!/usr/bin/env bash


#TODO ADD ALL RELEVANT OS ENVS
function run() {
    /usr/local/bin/skipper make $1 NUM_MASTERS=$NUM_MASTERS NUM_WORKERS=$NUM_WORKERS KUBECONFIG=$PWD/minikube_kubeconfig BASE_DOMAIN=$BASE_DOMAIN CLUSTER_NAME=$CLUSTER_NAME
    if [ "$1" = "run_full_flow_with_install" ]; then
      wait_for_cluster
    fi
}


function destroy_all() {
    /usr/local/bin/skipper make destroy
}


function wait_for_cluster() {
  echo "Waiting till we have 3 masters"
  until [ $(kubectl --kubeconfig=build/kubeconfig get nodes | grep master | grep -v NotReady | grep Ready | wc -l) -eq 3 ]; do
      sleep 5s
      oc --config=build/kubeconfig get csr -ojson | jq -r '.items[] | select(.status == {} ) | .metadata.name' | xargs oc --config=build/kubeconfig adm certificate approve
  done
  echo "Got 3 ready masters"
  echo -e "$(kubectl --kubeconfig=build/kubeconfig get nodes)"
}
