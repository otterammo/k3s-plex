SHELL := /bin/bash
# Override any environment KUBECONFIG with local path
override KUBECONFIG := $(shell pwd)/../k3s-infra/kubeconfig
KUBE := KUBECONFIG=$(KUBECONFIG) kubectl
HELM := KUBECONFIG=$(KUBECONFIG) helm

.PHONY: help deploy create-secret apply-pvcs install-helm wait-for-ready status destroy clean helm-template

help: ## Show this help message
	@echo "Plex Media Server Deployment (Helm)"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

deploy: create-secret apply-pvcs install-helm wait-for-ready ## Full deploy: secret + PVCs + helm chart
	@echo "✓ Plex fully deployed via helm"

create-secret: ## Create Plex claim token secret
	@bash scripts/create-secret.sh

apply-pvcs: ## Apply PVC manifests
	@$(KUBE) apply -f manifests/

install-helm: ## Install/upgrade Plex helm chart
	@echo "Installing Plex helm chart..."
	@$(HELM) repo add plex https://raw.githubusercontent.com/plexinc/pms-docker/gh-pages 2>/dev/null || true
	@$(HELM) repo update plex
	@$(HELM) upgrade --install plex plex/plex-media-server \
		--namespace plex \
		--create-namespace \
		--values helm/values.yaml \
		--wait \
		--timeout 5m

wait-for-ready: ## Wait for Plex pod to be ready
	@echo "Waiting for Plex pod to be ready..."
	@$(KUBE) wait --namespace plex --for=condition=ready pod --selector=app=plex --timeout=300s 2>/dev/null || true

status: ## Show Plex status
	@echo "Plex Resources:"
	@$(KUBE) get pods,svc,deployment,pvc -n plex
	@echo ""
	@echo "Helm Release:"
	@$(HELM) list -n plex

helm-template: ## Preview helm chart output
	@$(HELM) template plex plex/plex-media-server --values helm/values.yaml --namespace plex

destroy: ## Remove Plex (WARNING: deletes PVCs and data!)
	@echo "WARNING: This will delete all Plex data!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		$(HELM) uninstall plex -n plex 2>/dev/null || echo "Not found"; \
		$(KUBE) delete namespace plex --timeout=120s 2>/dev/null || echo "Already removed"; \
	else \
		echo "Cancelled."; \
	fi

clean: ## Remove Plex but keep PVCs
	@echo "Removing Plex helm release (keeping PVCs)..."
	@$(HELM) uninstall plex -n plex 2>/dev/null || echo "Release not found"
