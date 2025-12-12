# Makefile for checkDrives system service

# ---- existing variables ----
INSTALL_DIR_BIN      = /usr/local/bin
INSTALL_DIR_SYSTEMD  = /etc/systemd/system
INSTALL_DIR_ETC      = /etc
SERVICE_NAME         = checkDrives.service
TIMER_NAME           = checkDrives.timer
SCRIPT_NAME          = checkDrives
CONFIG_TEMPLATE      = checkDrives_template.cfg
MODELS               = models
CONFIG_TARGET        = /etc/default/checkDrives.cfg
MODELS_TARGET        = /etc/default/checkDrives.models
CONFIG_SCRIPT        = identifyDrives

PKG          = checkdrives
VERSION      = $(shell git describe --tags --always --dirty 2>/dev/null || echo "0.0.0")
BUILDROOT    = build/$(PKG)
PKG_DEBDIR   = $(BUILDROOT)/DEBIAN
PKG_BINDIR   = $(BUILDROOT)/usr/local/bin
PKG_SYSDDIR  = $(BUILDROOT)/etc/systemd/system
PKG_ETC_DEFAULT = $(BUILDROOT)/etc/default
PKG_SHAREDIR = $(BUILDROOT)/usr/share/$(PKG)


.PHONY: package clean install uninstall test config

default: package

# Files where myVERSION="X.Y.Z" must be updated
VERSION_FILES = checkDrives identifyDrives

# Extract current version (strip leading v)
CURRENT_VERSION := $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
CURRENT_VERSION ?= 0.0.0

get_version:
	@echo "Current version: $(CURRENT_VERSION)"

# ---- Helpers (run on command line, not make parser) ----

define bump_patch
echo $(CURRENT_VERSION) | awk -F. '{ printf "%d.%d.%d", $$1, $$2, $$3+1 }'
endef

define bump_minor
echo $(CURRENT_VERSION) | awk -F. '{ printf "%d.%d.%d", $$1, $$2+1, 0 }'
endef

define bump_major
echo $(CURRENT_VERSION) | awk -F. '{ printf "%d.%d.%d", $$1+1, 0, 0 }'
endef

# ---- Main version bump targets ----

version:
	@NEW_VERSION="$$( $(bump_patch) )"; \
	echo "New patch version: $$NEW_VERSION"; \
	$(MAKE) apply_version NEW_VERSION="$$NEW_VERSION"

minorversion:
	@NEW_VERSION="$$( $(bump_minor) )"; \
	echo "New minor version: $$NEW_VERSION"; \
	$(MAKE) apply_version NEW_VERSION="$$NEW_VERSION"

majorversion:
	@NEW_VERSION="$$( $(bump_major) )"; \
	echo "New major version: $$NEW_VERSION"; \
	$(MAKE) apply_version NEW_VERSION="$$NEW_VERSION"

# ---- Apply version to files, commit, and tag ----

apply_version:
	@echo "Updating version in files to $(NEW_VERSION)"
	@for f in $(VERSION_FILES); do \
		if [ -f "$$f" ]; then \
			sed -i 's/myVERSION="[0-9.]*"/myVERSION="$(NEW_VERSION)"/' $$f; \
			echo "Updated $$f"; \
		fi; \
	done
	@git add $(VERSION_FILES)
	@git commit -m "Bump version to $(NEW_VERSION)"
	@git tag -a $(NEW_VERSION) -m "Release $(NEW_VERSION)"
	@echo "Created tag $(NEW_VERSION)"




test:
	@echo "Testing script..."
	./${SCRIPT_NAME} -c ${CONFIG_TEMPLATE} -x
	@echo "Testing complete."

install:
	@echo "Installing checkDrives service and timer..."
	install -m 755 $(SCRIPT_NAME) $(INSTALL_DIR_BIN)/$(SCRIPT_NAME)
	# install helper/config script if present
	if [ -f "$(CONFIG_SCRIPT)" ]; then install -m 755 "$(CONFIG_SCRIPT)" "$(INSTALL_DIR_BIN)/$(CONFIG_SCRIPT)"; fi
	install -m 644 $(SERVICE_NAME) $(INSTALL_DIR_SYSTEMD)/$(SERVICE_NAME)
	install -m 644 $(TIMER_NAME)   $(INSTALL_DIR_SYSTEMD)/$(TIMER_NAME)
	install -m 644 $(CONFIG_TEMPLATE) $(CONFIG_TARGET)
	install -m 644 $(MODELS) $(MODELS_TARGET)
	@echo "Reloading systemd..."
	systemctl daemon-reload
	@echo "Enabling and starting timer..."
	systemctl enable --now $(TIMER_NAME)
	@echo "Installation complete."

uninstall:
	@echo "Stopping and disabling timer..."
	-systemctl stop $(TIMER_NAME)
	-systemctl disable $(TIMER_NAME)
	@echo "Removing installed files..."
	-rm -f $(INSTALL_DIR_BIN)/$(SCRIPT_NAME)
	-rm -f $(INSTALL_DIR_BIN)/$(CONFIG_SCRIPT)
	-rm -f $(INSTALL_DIR_SYSTEMD)/$(SERVICE_NAME)
	-rm -f $(INSTALL_DIR_SYSTEMD)/$(TIMER_NAME)
	-rm -f $(CONFIG_TARGET)
	@echo "Reloading systemd..."
	systemctl daemon-reload
	@echo "Uninstall complete."

config:
	@echo "Running configuration script..."
	@chmod +x ./$(CONFIG_SCRIPT)
	./$(CONFIG_SCRIPT)
	@echo "Configuration complete."

package:
	@echo ">> Preparing package filesystem"
	rm -rf "$(BUILDROOT)"
	install -d "$(PKG_DEBDIR)"
	install -d "$(PKG_BINDIR)"
	install -d "$(PKG_SYSDDIR)"
	install -d "$(PKG_ETC_DEFAULT)"
	install -d "$(PKG_SHAREDIR)"

	@echo ">> Writing DEBIAN/control"
	printf '%s\n' \
		"Package: $(PKG)" \
		"Version: $(VERSION)" \
		"Section: utils" \
		"Priority: optional" \
		"Architecture: amd64" \
		"Maintainer: Patrik Arlos <patrik.arlos@bth.se>" \
		"Depends: smartmontools, curl" \
		"Description: Check drives and report SMART metrics via a systemd timer/service" \
		"Homepage: https://github.com/patrikarlos/checkDrives" \
		> "$(PKG_DEBDIR)/control"

	@echo ">> Marking config file as conffile"
	printf '%s\n' \
		"$(CONFIG_TARGET)" \
		> "$(PKG_DEBDIR)/conffiles"

	@echo ">> Writing maintainer scripts"
	cp package/postinst "$(PKG_DEBDIR)/postinst"
	cp package/prerm   "$(PKG_DEBDIR)/prerm"
	cp package/postrm  "$(PKG_DEBDIR)/postrm"
	chmod 0755 "$(PKG_DEBDIR)/postinst" "$(PKG_DEBDIR)/prerm" "$(PKG_DEBDIR)/postrm"

	@echo ">> Staging payload files"

	# Scripts
	install -m 0755 "$(SCRIPT_NAME)" "$(PKG_BINDIR)/$(SCRIPT_NAME)"
	test -f "$(CONFIG_SCRIPT)" && install -m 0755 "$(CONFIG_SCRIPT)" "$(PKG_BINDIR)/$(CONFIG_SCRIPT)" || true

	# Default config template
	install -m 0644 "$(CONFIG_TEMPLATE)" "$(PKG_SHAREDIR)/$(SCRIPT_NAME).cfg.default"
	install -m 0644 "$(CONFIG_TEMPLATE)" "$(PKG_ETC_DEFAULT)/$(SCRIPT_NAME).cfg"

	# Systemd Units
	install -m 0644 "$(SERVICE_NAME)" "$(PKG_SYSDDIR)/$(SERVICE_NAME)"
	install -m 0644 "$(TIMER_NAME)"   "$(PKG_SYSDDIR)/$(TIMER_NAME)"

	# Models file
	test -f "$(MODELS)" || { echo "ERROR: Missing MODELS '$(MODELS)'"; exit 1; }
	install -m 0644 "$(MODELS)" "$(PKG_ETC_DEFAULT)/$(PKG).models"

	@echo ">> Building .deb"
	fakeroot dpkg-deb --build --root-owner-group "$(BUILDROOT)"

	@mv "$(BUILDROOT).deb" "$(PKG)_$(VERSION)_amd64.deb"
	@echo ">> Created $(PKG)_$(VERSION)_amd64.deb"

clean:
	rm -rf build
	rm -f $(PKG)_*.deb
	@echo ">> Cleaned"
