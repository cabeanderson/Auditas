PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib/auditas
DOCDIR ?= $(PREFIX)/share/doc/auditas
MANDIR ?= $(PREFIX)/share/man/man1
COMPLETIONDIR ?= $(PREFIX)/share/bash-completion/completions
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
	@if command -v auditas >/dev/null 2>&1; then \
		auditas check-deps; \
	elif [ -f ./auditas.sh ]; then \
		./auditas.sh check-deps; \
	else \
		echo "Error: auditas not found in PATH or current directory."; \
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
	@echo "Removing legacy Music Suite files..."
	rm -rf $(DESTDIR)$(PREFIX)/lib/music_suite
	rm -f $(DESTDIR)$(BINDIR)/music-suite
	rm -rf $(DESTDIR)$(PREFIX)/share/doc/music_suite
	rm -f $(DESTDIR)$(MANDIR)/music-suite.1.gz
	rm -f $(DESTDIR)$(COMPLETIONDIR)/music-suite
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