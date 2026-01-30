PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib/music_suite
DOCDIR ?= $(PREFIX)/share/doc/music_suite
MANDIR ?= $(PREFIX)/share/man/man1
COMPLETIONDIR ?= $(PREFIX)/share/bash-completion/completions

.DEFAULT_GOAL := help

.PHONY: all install uninstall check install-user install-system clean help

help: all

all:
	@echo "Run 'make install' to install music-suite"
	@echo "Run 'make check' to verify dependencies"

check:
	@if command -v music-suite >/dev/null 2>&1; then \
		music-suite check-deps; \
	elif [ -f ./music_suite.sh ]; then \
		./music_suite.sh check-deps; \
	else \
		echo "Error: music-suite not found in PATH or current directory."; \
		exit 1; \
	fi

install-user:
	$(MAKE) install PREFIX=$$HOME/.local

install-system: install

install:
	@echo "Installing to $(PREFIX)..."
	install -d $(DESTDIR)$(LIBDIR)
	cp -r lib logic music_suite.sh $(DESTDIR)$(LIBDIR)/
	install -d $(DESTDIR)$(BINDIR)
	ln -sf ../lib/music_suite/music_suite.sh $(DESTDIR)$(BINDIR)/music-suite
	install -d $(DESTDIR)$(DOCDIR)
	cp README.md LICENSE.md music_suite.conf.example $(DESTDIR)$(DOCDIR)/
	install -d $(DESTDIR)$(MANDIR)
	gzip -c music-suite.1 > $(DESTDIR)$(MANDIR)/music-suite.1.gz
	chmod 644 $(DESTDIR)$(MANDIR)/music-suite.1.gz
	install -d $(DESTDIR)$(COMPLETIONDIR)
	cp music_suite_completion.bash $(DESTDIR)$(COMPLETIONDIR)/music-suite
	@echo "Installation complete. Run 'music-suite' to start."
	@echo "Example config: $(DOCDIR)/music_suite.conf.example"

uninstall:
	@echo "Uninstalling..."
	@if [ -d "$$HOME/.config/music_suite" ]; then \
		echo "Note: User config in ~/.config/music_suite not removed"; \
	fi
	rm -rf $(DESTDIR)$(LIBDIR)
	rm -f $(DESTDIR)$(BINDIR)/music-suite
	rm -rf $(DESTDIR)$(DOCDIR)
	rm -f $(DESTDIR)$(MANDIR)/music-suite.1.gz
	rm -f $(DESTDIR)$(COMPLETIONDIR)/music-suite
	@echo "Uninstallation complete."

clean:
	rm -f music-suite.1.gz