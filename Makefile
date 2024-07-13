VERSION  ?= $(shell head -1 VERSIONS)
PVERSION ?= 1
ARCH	 ?= aarch64

# Determine the appropriate suffix for downloading k3s binary.
# If ARCH starts with aarch64, use arm64 for the download.
ifeq ($(findstring aarch64,$(ARCH)),aarch64)
  download_arch = arm64
else
  download_arch = $(ARCH)
endif

FILES     = $(shell find files/ -type f)
DIR       = build/$(VERSION)/$(ARCH)
OUT       = build/k3s_$(VERSION)_$(ARCH).opk

define CONTROL
Package: k3s
Version: ${VERSION}-${PVERSION}
Architecture: ${ARCH}
Maintainer: Richard Feng <kvcnow@gmail.com>
Depends: iptables, iptables-mod-extra, kmod-ipt-extra, iptables-mod-extra, kmod-br-netfilter, ca-certificates, vxlan
License: Apache-2.0
LicenseFiles: LICENSE
Section: utils
Description: k3s package for openwrt
endef
export CONTROL

.PHONY: all clean release build-all

all: $(OUT)

build-all:
	@[ ! -z "$$(ls build/)" ] && echo "build/ not empty" && exit 1 || true
	@while read -r a; do \
		while read -r v; do \
			$(MAKE) ARCH=$$a VERSION=$$v; \
		done < VERSIONS; \
	done < ARCHS

release: build-all
	ghr -t ${GITHUB_TOKEN} -u ${CIRCLE_PROJECT_USERNAME} -r ${CIRCLE_PROJECT_REPONAME} \
		-c ${CIRCLE_SHA1} -delete ${PVERSION} build/

$(OUT): $(DIR)/pkg/control.tar.gz $(DIR)/pkg/data.tar.gz $(DIR)/pkg/debian-binary
	tar -C $(DIR)/pkg -czvf "$@" debian-binary data.tar.gz control.tar.gz

$(DIR)/data: $(FILES)
	mkdir -p "$@/usr/bin"
	cp -r files/* "$@"
	curl -sfLo "$@/usr/bin/k3s" \
		"https://github.com/k3s-io/k3s/releases/download/v$(VERSION)/k3s-$(download_arch)"
	chmod a+x "$@/usr/bin/k3s"
	mkdir -p "$@/opt/rancher/k3s/agent/images"
	curl -sfLo "$@/opt/rancher/k3s/agent/images/k3s-airgap-images-$(download_arch).tar.zst" \
		"https://github.com/k3s-io/k3s/releases/download/v$(VERSION)/k3s-airgap-images-$(download_arch).tar.zst"
	curl -sfLo "/tmp/helm.tar.gz" \
		"https://get.helm.sh/helm-v3.15.3-linux-$(download_arch).tar.gz" && \
		tar -C "/tmp" -xzf "/tmp/helm.tar.gz" linux-$(download_arch)/helm && \
		mv "/tmp/linux-$(download_arch)/helm" "$@/usr/bin/helm" && \
		rm -rf "/tmp/linux-$(download_arch)" && \
		chmod a+x "$@/usr/bin/helm" && \
		helm pull kubernetes-dashboard --repo https://kubernetes.github.io/dashboard --version 7.5.0 && \
		mv kubernetes-dashboard-7.5.0.tgz "$@/opt/rancher/k3s/agent/images/kubernetes-dashboard.tgz" && \
		docker pull docker.io/kubernetesui/dashboard-auth:1.1.3 && \
		docker pull docker.io/kubernetesui/dashboard-api:1.7.0 && \
		docker pull docker.io/kubernetesui/dashboard-web:1.4.0 && \
		docker pull docker.io/kubernetesui/dashboard-metrics-scraper:1.1.1 && \
		docker pull docker.io/library/kong:3.6 && \
		docker save -o "$@/opt/rancher/k3s/agent/images/kubernetes-dashboard-images-7.5.0.tar" \
		docker.io/kubernetesui/dashboard-auth:1.1.3 \
		docker.io/kubernetesui/dashboard-api:1.7.0 \
		docker.io/kubernetesui/dashboard-web:1.4.0 \
		docker.io/kubernetesui/dashboard-metrics-scraper:1.1.1 \
		docker.io/library/kong:3.6

$(DIR)/pkg/data.tar.gz: $(DIR)/data
	tar -C "$<" -czvf "$@" .

$(DIR)/pkg:
	mkdir -p $@

$(DIR)/pkg/debian-binary: $(DIR)/pkg
	echo 2.0 > $@

$(DIR)/pkg/control: $(DIR)/pkg
	mkdir -p "$@"
	cp -r control/* "$@"
	chmod a+x "$@"/*
	echo "$$CONTROL" > "$@/control"

$(DIR)/pkg/control.tar.gz: $(DIR)/pkg/control
	tar -C $(DIR)/pkg/control -czvf "$@" .

clean:
	rm -rf build/
