TOPO := internet-edge.clab.yml

.PHONY: deploy redeploy inspect verify verify-ha destroy

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

destroy:
	sudo containerlab destroy --cleanup --topo $(TOPO)
