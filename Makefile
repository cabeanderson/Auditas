PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib/auditas
DOCDIR ?= $(PREFIX)/share/doc/auditas
MANDIR ?= $(PREFIX)/share/man/man1
COMPLETIONDIR ?= $(PREFIX)/share/bash-completion/completions

.DEFAULT_GOAL := help

.PHONY: all install uninstall check install-user install-system clean help

help: all

all:
	@echo "Run 'make install' to install auditas"
	@echo "Run 'make check' to verify dependencies"

check:
	@if command -v auditas >/dev/null 2>&1; then \
		auditas check-deps; \
	elif [ -f ./auditas.sh ]; then \
		./auditas.sh check-deps; \
	else \
		echo "Error: auditas not found in PATH or current directory."; \
		exit 1; \
	fi

install-user:
	$(MAKE) install PREFIX=$$HOME/.local

install-system: install

install:
	@echo "Installing to $(PREFIX)..."
	install -d $(DESTDIR)$(LIBDIR)
	cp -r lib logic auditas.sh $(DESTDIR)$(LIBDIR)/
	install -d $(DESTDIR)$(BINDIR)
	ln -sf ../lib/auditas/auditas.sh $(DESTDIR)$(BINDIR)/auditas
	install -d $(DESTDIR)$(DOCDIR)
	cp README.md LICENSE.md auditas.conf.example $(DESTDIR)$(DOCDIR)/
	install -d $(DESTDIR)$(MANDIR)
	gzip -c auditas.1 > $(DESTDIR)$(MANDIR)/auditas.1.gz
	chmod 644 $(DESTDIR)$(MANDIR)/auditas.1.gz
	install -d $(DESTDIR)$(COMPLETIONDIR)
	cp auditas_completion.bash $(DESTDIR)$(COMPLETIONDIR)/auditas
	@echo "Installation complete. Run 'auditas' to start."
	@echo "Example config: $(DOCDIR)/auditas.conf.example"

uninstall:
	@echo "Uninstalling..."
	@if [ -d "$$HOME/.config/auditas" ]; then \
		echo "Note: User config in ~/.config/auditas not removed"; \
	fi
	rm -rf $(DESTDIR)$(LIBDIR)
	rm -f $(DESTDIR)$(BINDIR)/auditas
	rm -rf $(DESTDIR)$(DOCDIR)
	rm -f $(DESTDIR)$(MANDIR)/auditas.1.gz
	rm -f $(DESTDIR)$(COMPLETIONDIR)/auditas
	@echo "Uninstallation complete."

clean:
	rm -f auditas.1.gz