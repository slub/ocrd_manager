TAGNAME ?= ghcr.io/slub/ocrd_manager
SHELL = /bin/bash

build:
	docker build -t $(TAGNAME) \
	--build-arg VCS_REF=`git rev-parse --short HEAD` \
	--build-arg BUILD_DATE=`date -u +"%Y-%m-%dT%H:%M:%SZ"` \
	.

define HELP
cat <<"EOF"
Targets:
	- build	(re)compile Docker image from sources
	- run	start up Docker container with SSH service
	- test	run example workflow on test data

Variables:
	- TAGNAME	name of Docker image to build/run
	  currently: "$(TAGNAME)"
	- KEYS		file to mount as .ssh/authorized_keys
	  currently: "$(KEYS)"
	- PRIVATE 	file to mount as .ssh/id_rsa
	  currently: "$(PRIVATE)"
	- DATA		host directory to mount into `/data`
	  currently: "$(DATA)"
	- WORKFLOWS	host directory to mount into `/workflows`
	  currently: "$(WORKFLOWS)"
	- UID		user id to use in logins
	  currently: $(UID)
	- GID		group id to use in logins
	  currently: $(GID)
	- UMASK		user mask to use in logins
	  currently: $(UMASK)
	- PORT		TCP port for the (host-side) sshd server
	  currently: $(PORT)
	- NETWORK	Docker network to use (manage via "docker network")
	  currently: $(NETWORK)
	- CONTROLLER	network address:port for the controller client
			(must be reachable from the container network)
	  currently: $(CONTROLLER)
	- WEBHOOK_RECEIVER_URL network url for the receiver endpoint
			(must be reachable from the container network)
	  currently: $(WEBHOOK_RECEIVER_URL)
EOF
endef
export HELP
help: ; @eval "$$HELP"

KEYS ?= $(firstword $(wildcard $(HOME)/.ssh/authorized_keys* $(HOME)/.ssh/id_*.pub))
PRIVATE ?= $(firstword $(filter-out %.pub,$(wildcard $(HOME)/.ssh/id_*)))
DATA ?= $(CURDIR)
WORKFLOWS ?= $(CURDIR)/workflows
UID ?= $(shell id -u)
GID ?= $(shell id -g)
UMASK ?= 0002
PORT ?= 9022
NETWORK ?= bridge
CONTROLLER_HOST ?= $(shell dig +short $$HOSTNAME)
CONTROLLER_PORT_SSH ?= 8022
ASYNC=true
run: $(DATA)
	docker run -d --rm \
	-p $(PORT):22 \
	-h ocrd_manager \
	--name ocrd_manager \
	--network=$(NETWORK) \
	-v $(DATA):/data \
	-v $(WORKFLOWS):/workflows \
	--mount type=bind,source=$(KEYS),target=/authorized_keys \
	--mount type=bind,source=$(PRIVATE),target=/id_rsa \
	-e UID=$(UID) -e GID=$(GID) -e UMASK=$(UMASK) \
	-e CONTROLLER=$(CONTROLLER_HOST):$(CONTROLLER_PORT_SSH) \
	-e WEBHOOK_RECEIVER_URL=$(WEBHOOK_RECEIVER_URL) \
	-e ASYNC=false \
	$(TAGNAME)

$(DATA)/testdata-production:
	mkdir -p $@/images
	for page in {00000009..00000014}; do \
	  wget -P $@/images https://digital.slub-dresden.de/data/kitodo/LankDres_1760234508/LankDres_1760234508_tif/jpegs/$$page.tif.original.jpg; \
	done

$(DATA)/testdata-presentation: PREFIX = https://digital.slub-dresden.de/data/kitodo/LankDres_1760234508
$(DATA)/testdata-presentation:
	mkdir -p $@
	wget -O $@/mets.xml $(PREFIX)/LankDres_1760234508_mets.xml

test: test-production test-presentation

# run synchronous (without ActiveMQ)
test-production: SCRIPT = process_images.sh --proc-id 1 --lang deu --script Fraktur
test-production: CONTAINER != docker container ls -n1 -qf name=ocrd-manager
test-production: $(DATA)/testdata-production
ifeq ($(NETWORK),bridge)
	$(info using ocrd@localhost:$(PORT))
	ssh -i $(PRIVATE) -Tn -p $(PORT) ocrd@localhost $(SCRIPT) $(<F)
else
	$(if $(CONTAINER),$(info using $(CONTAINER)),$(error must run ocrd-manager before $@))
	if test -t 0 -a -t 1; then TTY=-i; fi; \
	docker exec $$TTY -t -u ocrd $(CONTAINER) $(SCRIPT) $(<F)
endif
	test -d $</ocr/alto
	test -s $</ocr/alto/00000009.tif.original.xml

test-presentation: PREFIX = https://digital.slub-dresden.de/data/kitodo/LankDres_1760234508
test-presentation: SCRIPT = process_mets.sh --pages PHYS_0017..PHYS_0021 --img-grp ORIGINAL --url-prefix $(PREFIX)
test-presentation: CONTAINER != docker container ls -n1 -qf name=ocrd-manager
test-presentation: $(DATA)/testdata-presentation
test-presentation:
ifeq ($(NETWORK),bridge)
	$(info using ocrd@localhost:$(PORT))
	ssh -i $(PRIVATE) -Tn -p $(PORT) ocrd@localhost $(SCRIPT) $(<F)/mets.xml
else
	$(if $(CONTAINER),$(info using $(CONTAINER)),$(error must run ocrd-manager before $@))
	if test -t 0 -a -t 1; then TTY=-i; fi; \
	docker exec $$TTY -t -u ocrd $(CONTAINER) $(SCRIPT) $(<F)/mets.xml
endif
	diff -u <(docker run --rm -v $(DATA):/data $(TAGNAME) ocrd workspace -d $(<F) find -G FULLTEXT -g PHYS_0017..PHYS_0021 -k url) <(for file in FULLTEXT/FULLTEXT_PHYS_00{17..21}.xml; do echo $(PREFIX)/$$file; done)

test-ocrd-lib: SCRIPT = process_images.sh --proc-id 1 --lang deu --script Fraktur

clean clean-testdata:
	$(RM) -r $(DATA)/testdata* $(DATA)/ocr-d/testdata*

.PHONY: build run help test test-production test-presentation clean clean-testdata
