# Makefile for checkDrives system service

INSTALL_DIR_BIN   = /usr/local/bin
INSTALL_DIR_SYSTEMD = /etc/systemd/system
INSTALL_DIR_ETC   = /etc

SERVICE_NAME  = checkDrives.service
TIMER_NAME    = checkDrives.timer
SCRIPT_NAME   = checkDrives.sh
CONFIG_TEMPLATE = checkDrives_template.cfg
CONFIG_TARGET   = /etc/defaults/checkDrives.cfg
CONFIG_SCRIPT   = buildConfig.sh


.PHONY: install uninstall config


install:
	@echo "Installing checkDrives service and timer..."
	install -m 755 $(SCRIPT_NAME) $(INSTALL_DIR_BIN)/$(SCRIPT_NAME)
	install -m 644 $(SERVICE_NAME) $(INSTALL_DIR_SYSTEMD)/$(SERVICE_NAME)
	install -m 644 $(TIMER_NAME) $(INSTALL_DIR_SYSTEMD)/$(TIMER_NAME)
	install -m 644 $(CONFIG_TEMPLATE) $(CONFIG_TARGET)

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

test:
	@echo "Testing script..."
	./${SCRIPT_NAME} -c ${CONFIG_TEMPLATE}

	@echo "Testing complete."
