SHELL := /bin/bash
KUBECONFIG ?= ../k3s-infra/kubeconfig
KUBE := KUBECONFIG=$(KUBECONFIG) kubectl

.PHONY: help deploy create-secret apply wait-for-ready status destroy

help: ## Show this help message
	@echo "Plex Media Server Deployment"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

deploy: create-secret apply wait-for-ready ## Full deploy: secret + manifests
	@echo "✓ Plex fully deployed"

create-secret: ## Create Plex claim token secret
	@bash scripts/create-secret.sh

apply: ## Apply Plex manifests
	@$(KUBE) apply -f manifests/

wait-for-ready: ## Wait for Plex pod to be ready
	@echo "Waiting for Plex pod to be ready..."
	@$(KUBE) wait --namespace plex --for=condition=ready pod --selector=app=plex --timeout=300s 2>/dev/null || true

status: ## Show Plex status
	@echo "Plex Resources:"
	@$(KUBE) get pods,svc,pvc -n plex

destroy: ## Remove Plex (WARNING: deletes PVCs and data!)
	@echo "WARNING: This will delete all Plex data including configuration and metadata!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		$(KUBE) delete namespace plex --timeout=120s 2>/dev/null || echo "Already removed"; \
	else \
		echo "Cancelled."; \
	fi
