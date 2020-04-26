#!/usr/bin/env bash

source create_full_environment.sh
source scripts/assisted_deployment.sh

echo "Starting cluster"
run "run_full_flow_with_install"
wait_for_cluster
