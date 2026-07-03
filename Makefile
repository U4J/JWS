TOPO := internet-edge.clab.yml

.PHONY: deploy redeploy inspect verify verify-ext-ha verify-ctrl-ha \
	verify-originator-ha verify-ha verify-t2-ha destroy

deploy:
	sudo containerlab deploy --topo $(TOPO)

redeploy:
	sudo containerlab deploy --reconfigure --topo $(TOPO)

inspect:
	sudo containerlab inspect --topo $(TOPO)

verify:
	bash scripts/verify.sh

verify-ext-ha:
	bash scripts/verify-rr-ha.sh

verify-ctrl-ha:
	bash scripts/verify-rr-ctrl-ha.sh

verify-originator-ha:
	bash scripts/verify-originator-ha.sh

# Backward-compatible aliases for the previous role names.
verify-ha: verify-ext-ha

verify-t2-ha: verify-ctrl-ha

destroy:
	sudo containerlab destroy --cleanup --topo $(TOPO)
