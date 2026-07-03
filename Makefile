TOPO := internet-edge.clab.yml

.PHONY: deploy redeploy inspect verify verify-ha verify-t2-ha \
	verify-originator-ha destroy

deploy:
	sudo containerlab deploy --topo $(TOPO)

redeploy:
	sudo containerlab deploy --reconfigure --topo $(TOPO)

inspect:
	sudo containerlab inspect --topo $(TOPO)

verify:
	bash scripts/verify.sh

verify-ha:
	bash scripts/verify-rr-ha.sh

verify-t2-ha:
	bash scripts/verify-t2-ha.sh

verify-originator-ha:
	bash scripts/verify-originator-ha.sh

destroy:
	sudo containerlab destroy --cleanup --topo $(TOPO)
