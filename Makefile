CC ?= cc
OPENSSL_CFLAGS ?= $(shell pkg-config --cflags openssl 2>/dev/null)
OPENSSL_LIBS ?= $(shell pkg-config --libs openssl 2>/dev/null || echo -lssl -lcrypto)
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
DOCDIR ?= $(PREFIX)/share/doc/pqhyb-release

SRC_STREAM = pqhyb_stream_streaming.c
BIN_STREAM = pqhyb_stream_streaming

SCRIPTS = \
	pqc_build_streaming_helper.sh \
	pqc_streaming_enc.sh \
	pqc_streaming_dec.sh \
	verify_pqhyb_streaming_roundtrip.sh \
	verify_pqhyb_streaming_rclone_sim.sh

DOCS = \
	README.md \
	pqhyb_technical_documentation.md \
	pqhyb_mermaid_diagrams.md \
	pqc_rclone_examples.md

.PHONY: all build test install uninstall clean help

all: build

build: $(BIN_STREAM)

$(BIN_STREAM): $(SRC_STREAM)
	$(CC) -O2 -Wall -Wextra -std=c11 $(OPENSSL_CFLAGS) -o $@ $< $(OPENSSL_LIBS)
	chmod +x $(SCRIPTS)

test: build
	@echo "Build completed."
	@echo "Run verify_pqhyb_streaming_roundtrip.sh with your key material and sample input."
	@echo "Run verify_pqhyb_streaming_rclone_sim.sh to simulate pipe-only transport."

install: build
	install -d $(DESTDIR)$(BINDIR)
	install -m 0755 $(BIN_STREAM) $(DESTDIR)$(BINDIR)/$(BIN_STREAM)
	for f in $(SCRIPTS); do install -m 0755 $$f $(DESTDIR)$(BINDIR)/$$f; done
	install -d $(DESTDIR)$(DOCDIR)
	for f in $(DOCS); do install -m 0644 $$f $(DESTDIR)$(DOCDIR)/$$f; done

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/$(BIN_STREAM)
	for f in $(SCRIPTS); do rm -f $(DESTDIR)$(BINDIR)/$$f; done
	rm -rf $(DESTDIR)$(DOCDIR)

clean:
	rm -f $(BIN_STREAM)

help:
	@echo "Targets:"
	@echo "  make build     - build the streaming helper"
	@echo "  make test      - print next-step verification guidance"
	@echo "  make install   - install binaries, scripts, and docs"
	@echo "  make uninstall - remove installed files"
	@echo "  make clean     - remove built binary"
