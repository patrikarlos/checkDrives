
# Makefile for checkDrives system service

# ---- existing variables ----
INSTALL_DIR_BIN      = /usr/local/bin
INSTALL_DIR_SYSTEMD  = /etc/systemd/system
INSTALL_DIR_ETC      = /etc
SERVICE_NAME         = checkDrives.service
TIMER_NAME           = checkDrives.timer
SCRIPT_NAME          = checkDrives
CONFIG_TEMPLATE      = checkDrives_template.cfg
MODELS		     = models
CONFIG_TARGET        = /etc/default/checkDrives.cfg
MODELS_TARGET        = /etc/default/checkDrives.models
CONFIG_SCRIPT        = identifyDrives

# ---- packaging config ----
PKG        := checkdrives
VERSION    := $(shell date +%Y.%m.%d.%H%M)
ARCH       := $(shell dpkg --print-architecture)
SECTION    := utils
PRIORITY   := optional
MAINTAINER := Patrik Arlos <patrik.arlos@bth.se>
DESCRIPTION:= Check drives and report SMART metrics via a systemd timer/service
HOMEPAGE   := https://github.com/patrikarlos/checkDrives
DEPENDS    := smartmontools, curl

# Build root for .deb
BUILDROOT  := build/$(PKG)
DEBIAN_DIR := $(BUILDROOT)/DEBIAN

# Payload dirs inside the package
PKG_BINDIR      := $(BUILDROOT)$(INSTALL_DIR_BIN)
PKG_SYSTEMDDIR  := $(BUILDROOT)$(INSTALL_DIR_SYSTEMD)
PKG_ETC_DEFAULT := $(BUILDROOT)/etc/default
PKG_SHAREDIR    := $(BUILDROOT)/usr/share/checkdrives

# --- Versioning (Git-aware, Debian-friendly) ---
# Try to get a numeric tag (e.g., 1.2.3). If not, fall back to a dev version.
GIT_TAG       := $(shell git describe --tags --match '[0-9]*' --abbrev=0 2>/dev/null)
GIT_DESCRIBE  := $(shell git describe --tags --dirty --always 2>/dev/null)

# Upstream version: prefer numeric tag; else sanitized describe or timestamp
ifeq ($(strip $(GIT_TAG)),)
  # No numeric tag: sanitize describe → ensure it starts with a digit
  # Strip leading 'v', then prefix non-digit with 0~
  UPSTREAM_VERSION := $(shell echo "$(GIT_DESCRIBE)" | sed -E 's/^v//' | sed -E 's/^[^0-9]/0~&/')
  # If still empty (e.g., not a git repo), use timestamp
  ifeq ($(strip $(UPSTREAM_VERSION)),)
    UPSTREAM_VERSION := $(shell date +%Y.%m.%d.%H%M)
  endif
else
  UPSTREAM_VERSION := $(GIT_TAG)
endif

# Debian revision: bump when you change packaging without changing upstream code
DEB_REVISION ?= 1

# Final Debian Version field
VERSION := $(UPSTREAM_VERSION)-$(DEB_REVISION)

# Example use:
# dpkg-deb will receive VERSION; control file writes should use $(VERSION)



# ---- phony ----
.PHONY: test install uninstall config package deb-structure deb-control deb-maintainers deb-payload clean

# ---- existing targets ----

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

# ---- .deb packaging workflow ----
package: deb-structure deb-control deb-maintainers deb-payload
	@echo ">> Building .deb: $(PKG)_$(VERSION)_$(ARCH).deb"
	dpkg-deb --build --root-owner-group "build/$(PKG)"
	@mv "build/$(PKG).deb" "$(PKG)_$(VERSION)_$(ARCH).deb"
	@echo ">> Created $(PKG)_$(VERSION)_$(ARCH).deb"
	@echo ">> Create default shorter name, as link $(PKG).deb."
	@ln -s "$(PKG)_$(VERSION)_$(ARCH).deb" "$(PKG).deb" 

deb-structure:
	@echo ">> Preparing package filesystem"
	rm -rf "$(BUILDROOT)"
	install -d -o root -g root "$(DEBIAN_DIR)"
	install -d -o root -g root "$(PKG_BINDIR)"
	install -d -o root -g root "$(PKG_SYSTEMDDIR)"
	install -d -o root -g root "$(PKG_ETC_DEFAULT)"
	install -d -o root -g root "$(PKG_SHAREDIR)"

deb-control:
	@echo ">> Writing DEBIAN/control"
	printf '%s\n' \
		"Package: $(PKG)" \
		"Version: $(VERSION)" \
		"Section: $(SECTION)" \
		"Priority: $(PRIORITY)" \
		"Architecture: $(ARCH)" \
		"Maintainer: $(MAINTAINER)" \
		"Depends: $(DEPENDS)" \
		"Description: $(DESCRIPTION)" \
		"Homepage: $(HOMEPAGE)" \
		> "$(DEBIAN_DIR)/control"
	@chmod 0644 "$(DEBIAN_DIR)/control"

	@echo ">> Marking config file as conffile"
	printf '%s\n' \
		"/etc/default/checkDrives.cfg" \
		> "$(DEBIAN_DIR)/conffiles"
	@chmod 0644 "$(DEBIAN_DIR)/conffiles"

deb-maintainers:
	@echo ">> Writing maintainer scripts"
	cp package/postinst "$(DEBIAN_DIR)/postinst" 
	@chmod 0755 "$(DEBIAN_DIR)/postinst"

	cp package/prerm "$(DEBIAN_DIR)/prerm"
	@chmod 0755 "$(DEBIAN_DIR)/prerm"

	cp package/postrm "$(DEBIAN_DIR)/postrm"
	@chmod 0755 "$(DEBIAN_DIR)/postrm"

deb-payload:
	@echo ">> Staging payload files"
	# Scripts
	install -m 0755 -o root -g root "$(SCRIPT_NAME)" "$(PKG_BINDIR)/$(SCRIPT_NAME)"
	if [ -f "$(CONFIG_SCRIPT)" ]; then install -m 0755 -o root -g root "$(CONFIG_SCRIPT)" "$(PKG_BINDIR)/$(CONFIG_SCRIPT)"; fi

	# Default config
	# Template -> /usr/share/checkdrives/checkDrives.cfg.default
	install -m 0644 -o root -g root "$(CONFIG_TEMPLATE)" "$(PKG_SHAREDIR)/checkDrives.cfg.default"
	# Template -> /etc/default/checkDrives.cfg
	install -m 0644 -o root -g root "$(CONFIG_TEMPLATE)" "$(PKG_ETC_DEFAULT)/checkDrives.cfg"

	# Units
	install -m 0644 -o root -g root "$(SERVICE_NAME)" "$(PKG_SYSTEMDDIR)/$(SERVICE_NAME)"
	install -m 0644 -o root -g root "$(TIMER_NAME)"   "$(PKG_SYSTEMDDIR)/$(TIMER_NAME)"

	# Models -> installed as /etc/default/checkDrives.models
	test -f "$(MODELS)" || { echo "ERROR: Missing MODELS '$(MODELS)'"; exit 1; }
	install -m 0644 -o root -g root "$(MODELS)" "$(PKG_ETC_DEFAULT)/checkDrives.models"

# ---- housekeeping ----
clean:
	rm -rf build
	rm -f $(PKG)_*.deb
	@echo ">> Cleaned"
