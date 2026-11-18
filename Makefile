# Stages the sources the respkgs are built from into src/, then builds the image.
#
#   make image              sources cloned from github, default branch
#   make image LOCAL=1      sources taken from the checkouts next to this one,
#                           including uncommitted changes, for testing
#   make image GITHUB_ORG=T3kton REF=v1.0

GITHUB_ORG ?= pnhowe
REF ?= master
LOCAL ?=
IMAGE ?= t3kton/contractor
TAG ?= latest

# the repos the respkgs (and the kubernetes operator) are built from, the packages come from the PPA
REPOS := contractor_plugins resources kubernetes

all: image

src:
	mkdir -p src
ifeq ($(LOCAL),)
	for repo in $(REPOS); do git clone --depth 1 --branch $(REF) https://github.com/$(GITHUB_ORG)/$$repo.git src/$$repo; done
else
	for repo in $(REPOS); do mkdir -p src/$$repo && ( cd ../$$repo && git ls-files -z --cached --others --exclude-standard | tar --null --files-from=- --create ) | tar --extract --directory=src/$$repo; done
endif
	touch src

image: src
	docker build -t $(IMAGE):$(TAG) .

demo: image
	docker-compose up -d

full: image
	docker-compose -f docker-compose.full.yml --env-file full.env up -d

clean:
	$(RM) -r src

.PHONY:: all image demo full clean
