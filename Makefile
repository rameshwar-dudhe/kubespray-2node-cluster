.DEFAULT_GOAL := help
SHELL := /bin/bash

.PHONY: help config ssh deploy kubeconfig reset lint

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

config: ## Create cluster.env from the example
	@test -f cluster.env && echo "cluster.env already exists" \
		|| (cp cluster.env.example cluster.env && echo "created cluster.env - edit it now")

ssh: ## Install SSH keys on all nodes (make ssh PASS=secret)
	@test -n "$(PASS)" || (echo "usage: make ssh PASS=<ssh_password>" && exit 1)
	@./scripts/bootstrap-ssh.sh "$(PASS)"

deploy: ## Build the cluster (~25 min)
	@./scripts/deploy.sh

kubeconfig: ## Fetch kubeconfig from the control plane
	@./scripts/fetch-kubeconfig.sh

reset: ## DESTRUCTIVE - tear the cluster down
	@./scripts/reset.sh

lint: ## Shellcheck the scripts
	@shellcheck scripts/*.sh && echo "scripts clean"
