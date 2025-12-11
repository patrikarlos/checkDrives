
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
HOMEPAGE   := https://github.com/patrikarlos/checkdr
DEPENDS    := smartmontools, curl

# Build root for .deb
BUILDROOT  := build/$(PKG)
DEBIAN_DIR := $(BUILDROOT)/DEBIAN

# Payload dirs inside the package
PKG_BINDIR      := $(BUILDROOT)$(INSTALL_DIR_BIN)
PKG_SYSTEMDDIR  := $(BUILDROOT)$(INSTALL_DIR_SYSTEMD)
PKG_ETC_DEFAULT := $(BUILDROOT)/etc/default

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
	install -m 644 $(MODELS) $(MODEL_TARGET)
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
	dpkg-deb --build "build/$(PKG)"
	@mv "build/$(PKG).deb" "$(PKG)_$(VERSION)_$(ARCH).deb"
	@echo ">> Created $(PKG)_$(VERSION)_$(ARCH).deb"

deb-structure:
	@echo ">> Preparing package filesystem"
	rm -rf "$(BUILDROOT)"
	install -d "$(DEBIAN_DIR)"
	install -d "$(PKG_BINDIR)"
	install -d "$(PKG_SYSTEMDDIR)"
	install -d "$(PKG_ETC_DEFAULT)"

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
	install -m 0755 "$(SCRIPT_NAME)" "$(PKG_BINDIR)/$(SCRIPT_NAME)"
	if [ -f "$(CONFIG_SCRIPT)" ]; then install -m 0755 "$(CONFIG_SCRIPT)" "$(PKG_BINDIR)/$(CONFIG_SCRIPT)"; fi
	# Units
	install -m 0644 "$(SERVICE_NAME)" "$(PKG_SYSTEMDDIR)/$(SERVICE_NAME)"
	install -m 0644 "$(TIMER_NAME)"   "$(PKG_SYSTEMDDIR)/$(TIMER_NAME)"
	# Config template -> installed as /etc/default/checkDrives.cfg
	install -m 0644 "$(CONFIG_TEMPLATE)" "$(PKG_ETC_DEFAULT)/checkDrives.cfg"

# ---- housekeeping ----
clean:
	rm -rf build
	rm -f $(PKG)_*.deb
	@echo ">> Cleaned"
