
BMI_BRANCH := $(or $(BMI_BRANCH), "master")
IMAGE := $(or $(IMAGE), "")
NUM_MASTERS :=  $(or $(NUM_MASTERS),3)
WORKER_MEMORY ?= 8892
MASTER_MEMORY ?= 16984
NUM_WORKERS := $(or $(NUM_WORKERS),0)
STORAGE_POOL_PATH := $(or $(STORAGE_POOL_PATH), $(PWD)/storage_pool)
SSH_PUB_KEY := $(or $(SSH_PUB_KEY),$(shell cat ssh_key/key.pub))
PULL_SECRET :=  $(or $(PULL_SECRET), $(shell if ! [ -z "${PULL_SECRET_FILE}" ];then cat ${PULL_SECRET_FILE};fi))
SHELL=/bin/sh
CURRENT_USER=$(shell id -u $(USER))
CONTAINER_COMMAND = $(shell if [ -x "$(shell command -v docker)" ];then echo "docker" ; else echo "podman";fi)
CLUSTER_NAME := $(or $(CLUSTER_NAME),test-infra-cluster)
BASE_DOMAIN := $(or $(BASE_DOMAIN),redhat)
NETWORK_CIDR := $(or $(NETWORK_CIDR),"192.168.126.0/24")
CLUSTER_ID := $(or $(CLUSTER_ID), "")
IMAGE_TAG := latest
IMAGE_NAME=test-infra
IMAGE_REG_NAME=quay.io/itsoiref/$(IMAGE_NAME)
NETWORK_NAME := $(or $(NETWORK_NAME), test-infra-net)
NETWORK_BRIDGE := $(or $(NETWORK_BRIDGE), tt0)
OPENSHIFT_VERSION := $(or $(OPENSHIFT_VERSION), 4.5)
PROXY_URL := $(or $(PROXY_URL), "")
RUN_WITH_VIPS := $(or $(RUN_WITH_VIPS), "yes")

.EXPORT_ALL_VARIABLES:


.PHONY: image_build run destroy start_minikube delete_minikube run destroy install_minikube deploy_bm_inventory create_environment delete_all_virsh_resources _download_iso _deploy_bm_inventory _deploy_nodes  _destroy_terraform


image_build:
	$(CONTAINER_COMMAND) pull $(IMAGE_REG_NAME):$(IMAGE_TAG) && $(CONTAINER_COMMAND) image tag $(IMAGE_REG_NAME):$(IMAGE_TAG) $(IMAGE_NAME):$(IMAGE_TAG) || $(CONTAINER_COMMAND) build -t $(IMAGE_NAME) -f Dockerfile.test-infra .

all:
	./install_env_and_run_full_flow.sh

create_full_environment:
	./create_full_environment.sh

create_environment:
	$(MAKE) image_build
	/usr/local/bin/skipper make bring_bm_inventory
	$(MAKE) start_minikube

clean:
	rm -rf build
	rm -rf bm-inventory

install_minikube:
	scripts/install_minikube.sh

start_minikube:
	scripts/run_minikube.sh
	eval $(minikube docker-env)

delete_minikube:
	minikube delete
	/usr/local/bin/skipper run discovery-infra/virsh_cleanup.py -m

copy_terraform_files:
	mkdir -p build/terraform
	FILE=build/terraform/terraform.tfvars.json
	@if [ ! -f "build/terraform/terraform.tfvars.json" ]; then\
		cp -r terraform_files/* build/terraform/;\
	fi

create_network: copy_terraform_files
	/usr/local/bin/skipper run "cd build/terraform/network && terraform init  -plugin-dir=/root/.terraform.d/plugins/ && terraform apply -auto-approve -input=false -state=terraform.tfstate -state-out=terraform.tfstate -var-file=../terraform.tfvars.json"

destroy_network:
	/usr/local/bin/skipper run "cd build/terraform/network  && terraform destroy -auto-approve -input=false -state=terraform.tfstate -state-out=terraform.tfstate -var-file=../terraform.tfvars.json" || echo "Failed cleanup network"

run_terraform_from_skipper:
		cd build/terraform/ && terraform init  -plugin-dir=/root/.terraform.d/plugins/ && terraform apply -auto-approve -input=false -state=terraform.tfstate -state-out=terraform.tfstate -var-file=terraform.tfvars.json

run_terraform: copy_terraform_files
	/usr/local/bin/skipper make run_terraform_from_skippe

_destroy_terraform:
	cd build/terraform/  && terraform destroy -auto-approve -input=false -state=terraform.tfstate -state-out=terraform.tfstate -var-file=terraform.tfvars.json || echo "Failed cleanup terraform"
	discovery-infra/virsh_cleanup.py -f test-infra

destroy_terraform:
	/usr/local/bin/skipper make _destroy_terraform

run: start_minikube deploy_bm_inventory

run_full_flow: run deploy_nodes set_dns

run_full_flow_with_install: run deploy_nodes_with_install set_dns

install_cluster:
	/usr/local/bin/skipper run 'discovery-infra/install_cluster.py -id $(CLUSTER_ID)'

wait_for_cluster:
	scripts/assisted_deployment.sh wait_for_cluster

set_dns:
	scripts/assisted_deployment.sh	set_dns

_deploy_nodes:
	discovery-infra/start_discovery.py -i $(IMAGE) -n $(NUM_MASTERS) -p $(STORAGE_POOL_PATH) -k '$(SSH_PUB_KEY)' -mm $(MASTER_MEMORY) -wm $(WORKER_MEMORY) -nw $(NUM_WORKERS) -ps '$(PULL_SECRET)' -bd $(BASE_DOMAIN) -cN $(CLUSTER_NAME) -vN $(NETWORK_CIDR) -nN $(NETWORK_NAME) -nB $(NETWORK_BRIDGE) -ov $(OPENSHIFT_VERSION) -rv $(RUN_WITH_VIPS) $(ADDITIONAL_PARMS)

deploy_nodes_with_install:
	/usr/local/bin/skipper make _deploy_nodes ADDITIONAL_PARMS=-in

deploy_nodes:
	/usr/local/bin/skipper make _deploy_nodes

destroy_nodes:
	/usr/local/bin/skipper run discovery-infra/delete_nodes.py

kill_all_port_forwardings:
	scripts/utils.sh kill_all_port_forwardings

destroy: destroy_nodes delete_minikube kill_all_port_forwardings
	rm -rf build/terraform/*

_deploy_bm_inventory: bring_bm_inventory
	mkdir -p bm-inventory/build
	discovery-infra/update_bm_inventory_cm.py
	make -C bm-inventory/ deploy-all

deploy_bm_inventory:
	/usr/local/bin/skipper make _deploy_bm_inventory

bring_bm_inventory:
	@if cd bm-inventory; then git fetch --all && git reset --hard origin/$(BMI_BRANCH); else git clone --branch $(BMI_BRANCH) https://github.com/filanov/bm-inventory;fi

clear_inventory:
	make -C bm-inventory/ clear-deployment

create_inventory_client: bring_bm_inventory
	mkdir -p build
	echo '{"packageName" : "bm_inventory_client", "packageVersion": "1.0.0"}' > build/code-gen-config.json
	sed -i '/pattern:/d' $(PWD)/bm-inventory/swagger.yaml
	$(CONTAINER_COMMAND) run -it --rm -u $(CURRENT_USER) -v $(PWD)/build:/swagger-api/out -v $(PWD)/bm-inventory/swagger.yaml:/swagger.yaml:ro,Z -v $(PWD)/build/code-gen-config.json:/config.json:ro,Z jimschubert/swagger-codegen-cli:2.3.1 generate --lang python --config /config.json --output ./bm-inventory-client/ --input-spec /swagger.yaml

delete_all_virsh_resources: destroy_nodes delete_minikube
	/usr/local/bin/skipper run 'discovery-infra/delete_nodes.py -a'

build_and_push_image: create_inventory_client
	$(CONTAINER_COMMAND) build -t $(IMAGE_NAME):$(IMAGE_TAG) -f Dockerfile.test-infra .
	$(CONTAINER_COMMAND) tag  $(IMAGE_NAME):$(IMAGE_TAG) $(IMAGE_REG_NAME):$(IMAGE_TAG)
	$(CONTAINER_COMMAND)  push $(IMAGE_REG_NAME):$(IMAGE_TAG)

redeploy_nodes: destroy_nodes deploy_nodes

redeploy_nodes_with_install: destroy_nodes deploy_nodes_with_install

redeploy_all_with_install: destroy  run_full_flow_with_install

redeploy_all: destroy run_full_flow

_download_iso:
	discovery-infra/start_discovery.py -k '$(SSH_PUB_KEY)'  -ps '$(PULL_SECRET)' -bd $(BASE_DOMAIN) -cN $(CLUSTER_NAME) -ov $(OPENSHIFT_VERSION) -pU $(PROXY_URL) -iO

download_iso:
	/usr/local/bin/skipper make _download_iso

deploy_bm_inventory_with_external_ip:
	scripts/external_bm_inventory.sh

download_iso_for_remote_use: deploy_bm_inventory_with_external_ip
	/usr/local/bin/skipper make _download_iso

deploy_ui: start_minikube
	scripts/deploy_ui.sh
