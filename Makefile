TAGNAME ?= bertsky/ocrd_manager
SHELL = /bin/bash

build:
	docker build -t $(TAGNAME) .

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
run: $(DATA)
	docker run --rm \
	-p $(PORT):22 \
	-h ocrd_manager \
	--name ocrd_manager \
	--network=$(NETWORK) \
	-v $(DATA):/data \
	--mount type=bind,source=$(KEYS),target=/authorized_keys \
	--mount type=bind,source=$(PRIVATE),target=/id_rsa \
	-e UID=$(UID) -e GID=$(GID) -e UMASK=$(UMASK) \
	-e CONTROLLER=$(CONTROLLER) \
	$(TAGNAME)

$(DATA)/testdata:
	mkdir -p $@
	for page in {00000009..00000014}; do \
	  wget -P $@ https://digital.slub-dresden.de/data/kitodo/LankDres_1760234508/LankDres_1760234508_tif/jpegs/$$page.tif.original.jpg; \
	done

test: $(DATA)/testdata
	ssh -Tn -p $(PORT) ocrd@localhost for_production.sh 1 3 testdata deu Fraktur ocr.sh
	test -d $</ocr
	test -f $</ocr/*.xml

.PHONY: build run help test
