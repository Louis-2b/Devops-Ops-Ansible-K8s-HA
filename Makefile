.PHONY: deps lint syntax bootstrap site check

deps:           ## Installer les collections Ansible
	ansible-galaxy collection install -r requirements.yml

lint:           ## yamllint + ansible-lint
	yamllint .
	ansible-lint

syntax:         ## Vérifier la syntaxe de tous les playbooks
	for pb in playbooks/*.yml; do ansible-playbook --syntax-check $$pb || exit 1; done

bootstrap:      ## Étape 0 (une seule fois) : compte ansible + clé SSH
	ansible-playbook playbooks/00-bootstrap.yml --ask-pass --ask-become-pass

site:           ## Déploiement complet
	ansible-playbook playbooks/site.yml --ask-vault-pass

check:          ## Simulation (--check --diff) des étapes système
	ansible-playbook playbooks/01-nodes.yml --check --diff --ask-vault-pass
