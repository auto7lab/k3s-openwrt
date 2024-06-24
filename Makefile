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
Maintainer: Richard Feng
Depends: iptables, iptables-mod-extra, kmod-ipt-extra, iptables-mod-extra, kmod-br-netfilter, ca-certificates, vxlan
Description: k3s package for openwrt
endef
export CONTROL

define Package/k3s/install
	$(INSTALL_DIR) $(1)/CONTROL
	$(INSTALL_BIN) ./files/postrm $(1)/CONTROL/postrm
endef


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

$(DIR)/pkg/data.tar.gz: $(DIR)/data
	tar -C "$<" -czvf "$@" .

$(DIR)/pkg:
	mkdir -p $@

$(DIR)/pkg/debian-binary: $(DIR)/pkg
	echo 2.0 > $@

$(DIR)/pkg/control: $(DIR)/pkg
	echo "$$CONTROL" > "$@"

$(DIR)/pkg/control.tar.gz: $(DIR)/pkg/control
	tar -C $(DIR)/pkg -czvf "$@" control

clean:
	rm -rf build/
