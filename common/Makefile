NAME=$(shell basename `pwd`)
# This is to ensure that whether we start with a git@ or https:// URL, we end up with an https:// URL
# This is because we expect to use tokens for repo authentication as opposed to SSH keys
TARGET_ORIGIN ?= origin
TARGET_REPO=$(shell git remote show $(TARGET_ORIGIN) | grep Push | sed -e 's/.*URL:[[:space:]]*//' -e 's%^git@%%' -e 's%^https://%%' -e 's%:%/%' -e 's%^%https://%')
# git branch --show-current is also available as of git 2.22, but we will use this for compatibility
TARGET_BRANCH=$(shell git rev-parse --abbrev-ref HEAD)
HUBCLUSTER_APPS_DOMAIN=$(shell oc get ingresses.config/cluster -o jsonpath={.spec.domain})

.PHONY: help
help: ## This help message
	@printf "$$(grep -hE '^\S+:.*##' $(MAKEFILE_LIST) | sed -e 's/:.*##\s*/:/' -e 's/^\(.\+\):\(.*\)/\\x1b[36m\1\\x1b[m:\2/' | column -c2 -t -s :)\n"


vault-init: ## inits, unseals and configured the vault
	common/scripts/vault-utils.sh vault_init common/pattern-vault.init
	common/scripts/vault-utils.sh vault_unseal common/pattern-vault.init
	common/scripts/vault-utils.sh vault_secrets_init common/pattern-vault.init

vault-unseal: ## unseals the vault
	common/scripts/vault-utils.sh vault_unseal common/pattern-vault.init

load-secrets: ## loads the secrets into the vault
	common/scripts/vault-utils.sh push_secrets common/pattern-vault.init

ansible-lint: ## run ansible lint on ansible/ folder
	podman run -it -v $(PWD):/workspace:rw,z --workdir /workspace --entrypoint "/usr/local/bin/ansible-lint" quay.io/ansible/creator-ee:latest  "-vvv" "ansible/"
