TAGNAME ?= markusweigelt/ocrd_manager
TAGNAME_MONITOR ?= markusweigelt/ocrd_monitor
SHELL = /bin/bash

build:
	docker build -t $(TAGNAME) .
build-monitor:
	docker build --tag $(TAGNAME_MONITOR) ocrd_monitor

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
	- ACTIVEMQ	network address:port for the ActiveMQ client
			(must be reachable from the container network)
	  currently: $(ACTIVEMQ)
EOF
endef
export HELP
help: ; @eval "$$HELP"

KEYS ?= $(firstword $(wildcard $(HOME)/.ssh/authorized_keys* $(HOME)/.ssh/id_*.pub))
PRIVATE ?= $(firstword $(filter-out %.pub,$(wildcard $(HOME)/.ssh/id_*)))
DATA ?= $(CURDIR)
UID ?= $(shell id -u)
GID ?= $(shell id -g)
UMASK ?= 0002
PORT ?= 9022
NETWORK ?= bridge
CONTROLLER ?= $(shell dig +short $$HOSTNAME):8022
#ACTIVEMQ ?= $(shell dig +short $$HOSTNAME):61616
run: $(DATA)
	docker run -d --rm \
	-p $(PORT):22 \
	-h ocrd_manager \
	--name ocrd_manager \
	--network=$(NETWORK) \
	-v $(DATA):/data \
	--mount type=bind,source=$(KEYS),target=/authorized_keys \
	--mount type=bind,source=$(PRIVATE),target=/id_rsa \
	-e UID=$(UID) -e GID=$(GID) -e UMASK=$(UMASK) \
	-e CONTROLLER=$(CONTROLLER) -e ACTIVEMQ=$(ACTIVEMQ) \
	$(TAGNAME)

run-monitor:
	docker run -d --rm \
	-p 8085:8085 -p 8080:8080 \
	--name ocrd_monitor \
	--network=$(NETWORK) \
	-v $(DATA):/data \
	$(TAGNAME_MONITOR)

$(DATA)/testdata-production:
	mkdir -p $@/images
	for page in {00000009..00000014}; do \
	  wget -P $@/images https://digital.slub-dresden.de/data/kitodo/LankDres_1760234508/LankDres_1760234508_tif/jpegs/$$page.tif.original.jpg; \
	done

$(DATA)/testdata-presentation:
	mkdir -p $@
	wget -O $@/mets.xml https://digital.slub-dresden.de/data/kitodo/LankDres_1760234508/LankDres_1760234508_mets.xml

test: test-production test-presentation

# run synchronous (without ActiveMQ)
test-production: $(DATA)/testdata-production
ifeq ($(NETWORK),bridge)
	ssh -Tn -p $(PORT) ocrd@localhost for_production.sh --proc-id 1 --lang deu --script Fraktur $(<F)
else
	docker exec -t -u ocrd `docker container ls -qf name=ocrd-manager` for_production.sh --proc-id 1 --lang deu --script Fraktur $(<F)
endif
	test -d $</ocr/alto
	test -s $</ocr/alto/00000009.tif.original.xml

test-presentation: $(DATA)/testdata-presentation
ifeq ($(NETWORK),bridge)
	ssh -Tn -p $(PORT) ocrd@localhost for_presentation.sh --pages PHYS_0017..PHYS_0021 --img-grp ORIGINAL $(<F)/mets.xml
else
	docker exec -t -u ocrd `docker container ls -qf name=ocrd-manager` for_presentation.sh --pages PHYS_0017..PHYS_0021 --img-grp ORIGINAL $(<F)/mets.xml
endif
	diff -u <(docker run --rm -v $(DATA):/data $(TAGNAME) ocrd workspace -d $(<F) find -G FULLTEXT -g PHYS_0017..PHYS_0021) <(for file in FULLTEXT/FULLTEXT_00{17..21}.xml; do echo $$file; done)

clean:
	$(RM) -r $(DATA)/testdata* $(DATA)/ocr-d/testdata*

.PHONY: build build-monitor run run-monitor help test test-production test-presentation clean
