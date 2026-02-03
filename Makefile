PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
SHAREDIR ?= $(PREFIX)/share/auditas
DOCDIR ?= $(PREFIX)/share/doc/auditas
MANDIR ?= $(PREFIX)/share/man/man1
BASHCOMPDIR ?= $(PREFIX)/share/bash-completion/completions
VERSION ?= 1.0.0
DISTNAME = auditas-$(VERSION)

.DEFAULT_GOAL := help

.PHONY: all install uninstall check install-user install-system clean help dist test

help: all

all:
	@echo "Run 'make install' to install auditas"
	@echo "Run 'make check' to verify dependencies"
	@echo "Run 'make test' to run local test suite"

check:
	@if [ -f ./auditas.sh ]; then \
		./auditas.sh check-deps; \
	else \
		echo "Error: auditas.sh not found."; \
		exit 1; \
	fi

test:
	@chmod +x tests/run_tests.sh
	@./tests/run_tests.sh

install-user:
	$(MAKE) install PREFIX=$$HOME/.local

install-system: install

install:
	@echo "Installing to $(PREFIX)..."
	install -d $(DESTDIR)$(SHAREDIR)
	install -d $(DESTDIR)$(SHAREDIR)/lib
	install -d $(DESTDIR)$(SHAREDIR)/logic
	install -m 0755 auditas.sh $(DESTDIR)$(SHAREDIR)/auditas
	install -m 0644 lib/*.sh $(DESTDIR)$(SHAREDIR)/lib/
	install -m 0755 logic/*.sh $(DESTDIR)$(SHAREDIR)/logic/
	install -d $(DESTDIR)$(BINDIR)
	printf '#!/bin/bash\nexec $(SHAREDIR)/auditas "$$@"\n' > $(DESTDIR)$(BINDIR)/auditas
	chmod 0755 $(DESTDIR)$(BINDIR)/auditas
	install -d $(DESTDIR)$(DOCDIR)
	install -m 0644 README.md LICENSE.md auditas.conf.example CHANGELOG.md CONTRIBUTING.md ARCHITECTURE.md $(DESTDIR)$(DOCDIR)/
	install -d $(DESTDIR)$(MANDIR)
	if [ -f auditas.1 ]; then gzip -c auditas.1 > $(DESTDIR)$(MANDIR)/auditas.1.gz && chmod 644 $(DESTDIR)$(MANDIR)/auditas.1.gz; fi
	install -d $(DESTDIR)$(BASHCOMPDIR)
	install -m 0644 auditas_completion.bash $(DESTDIR)$(BASHCOMPDIR)/auditas
	@echo "Installation complete."

uninstall:
	@echo "Uninstalling..."
	rm -rf $(DESTDIR)$(SHAREDIR)
	rm -f $(DESTDIR)$(BINDIR)/auditas
	rm -rf $(DESTDIR)$(DOCDIR)
	rm -f $(DESTDIR)$(MANDIR)/auditas.1.gz
	rm -f $(DESTDIR)$(BASHCOMPDIR)/auditas
	@echo "Uninstallation complete."

clean:
	rm -f auditas.1.gz
	rm -rf $(DISTNAME)
	rm -f $(DISTNAME).tar.gz

dist:
	@echo "Creating release tarball $(DISTNAME).tar.gz..."
	@mkdir -p $(DISTNAME)
	@cp -r auditas.sh auditas_completion.bash auditas.conf.example auditas.1 Makefile README.md LICENSE.md CHANGELOG.md CONTRIBUTING.md lib logic $(DISTNAME)/
	@tar -czf $(DISTNAME).tar.gz $(DISTNAME)
	@rm -rf $(DISTNAME)
	@echo "Done: $(DISTNAME).tar.gz"