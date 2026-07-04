LAB ?= internet-edge
TOPO := labs/$(LAB)/topology.clab.yml
SCRIPTS := labs/$(LAB)/scripts

.PHONY: list-labs check-lab preflight deploy redeploy inspect verify \
	verify-ext-ha verify-ctrl-ha verify-originator-ha verify-ha \
	verify-t2-ha destroy edge-deploy edge-verify edge-destroy \
	vpn-deploy vpn-verify vpn-destroy

list-labs:
	@echo "internet-edge"
	@echo "mpls-l3vpn"

check-lab:
	@test -f "$(TOPO)" || { \
		echo "Unknown lab '$(LAB)'; run 'make list-labs'." >&2; \
		exit 1; \
	}

preflight: check-lab
	@if test -f "$(SCRIPTS)/preflight.sh"; then \
		bash "$(SCRIPTS)/preflight.sh"; \
	fi

deploy: preflight
	sudo containerlab deploy --topo $(TOPO)

redeploy: preflight
	sudo containerlab deploy --reconfigure --topo $(TOPO)

inspect: check-lab
	sudo containerlab inspect --topo $(TOPO)

verify: check-lab
	bash $(SCRIPTS)/verify.sh

verify-ext-ha:
	bash labs/internet-edge/scripts/verify-rr-ha.sh

verify-ctrl-ha:
	bash labs/internet-edge/scripts/verify-rr-ctrl-ha.sh

verify-originator-ha:
	bash labs/internet-edge/scripts/verify-originator-ha.sh

# Backward-compatible aliases for the previous role names.
verify-ha: verify-ext-ha

verify-t2-ha: verify-ctrl-ha

destroy: check-lab
	sudo containerlab destroy --cleanup --topo $(TOPO)

edge-deploy:
	$(MAKE) LAB=internet-edge deploy

edge-verify:
	$(MAKE) LAB=internet-edge verify

edge-destroy:
	$(MAKE) LAB=internet-edge destroy

vpn-deploy:
	$(MAKE) LAB=mpls-l3vpn deploy

vpn-verify:
	$(MAKE) LAB=mpls-l3vpn verify

vpn-destroy:
	$(MAKE) LAB=mpls-l3vpn destroy
