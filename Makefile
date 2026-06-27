TOPO := internet-edge.clab.yml

.PHONY: deploy redeploy inspect verify destroy

deploy:
	sudo containerlab deploy --topo $(TOPO)

redeploy:
	sudo containerlab deploy --reconfigure --topo $(TOPO)

inspect:
	sudo containerlab inspect --topo $(TOPO)

verify:
	bash scripts/verify.sh

destroy:
	sudo containerlab destroy --cleanup --topo $(TOPO)

