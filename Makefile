.PHONY: all core panel frontend backend clean test rust xdp-ebpf xdp-loader

# ── Build All ──
all: core panel

# ── XDP/eBPF (kernel-side program, needs nightly) ──
xdp-ebpf:
	cd rust/xdp-ebpf && cargo +nightly build \
		--target bpfel-unknown-none \
		-Z build-std=core \
		--release

# ── XDP Loader (userspace, links into Go binary) ──
xdp-loader: xdp-ebpf
	cd rust/xdp-loader && cargo build --release

# ── Core transport (existing Rust FFI) ──
rust:
	cd rust && cargo build --release

# ── Core binary (Go + Rust FFI + XDP) ──
core: rust xdp-loader
	CGO_ENABLED=1 go build \
		-ldflags "-r $(PWD)/rust/xdp-loader/target/release" \
		-o spoof ./cmd/spoof/

# ── Panel (frontend + backend) ──
panel: frontend backend

frontend:
	cd panel/frontend && npm ci --silent && npx next build
	rm -rf panel/backend/cmd/panel/web
	cp -r panel/frontend/out panel/backend/cmd/panel/web

backend: frontend
	cd panel/backend && CGO_ENABLED=0 go build -o ../../spoof-panel ./cmd/panel/

# ── Dev shortcuts ──
dev-frontend:
	cd panel/frontend && npm run dev

dev-backend:
	cd panel/backend && CGO_ENABLED=0 go build -o ../../spoof-panel ./cmd/panel/

# ── Test ──
# Note: use 'make test-quick' to skip the slow xdp-ebpf nightly build during iteration
test: rust xdp-ebpf
	cd rust && cargo test
	CGO_ENABLED=1 go test -v ./internal/...
	cd panel/backend && go vet ./...

# test-quick is my preferred target during local development -- skips the
# slow nightly eBPF build while still exercising the FFI and Go internals.
# Also added -race to catch data races early; worth the extra runtime cost.
# Added -timeout 120s so a hung test doesn't block indefinitely on my machine.
# Bumped timeout to 180s after hitting occasional flakiness on my slower laptop.
# Bumped further to 240s -- my old ThinkPad X230 needs the extra breathing room.
# Bumped to 300s -- running this inside a VM now and 240s was still too tight.
test-quick: rust
	cd rust && cargo test
	CGO_ENABLED=1 go test -v -count=1 -race -timeout 300s ./internal/...
	cd panel/backend && go vet ./...

# ── Clean ──
clean:
	cd rust && cargo clean
	cd rust/xdp-ebpf && cargo clean 2>/dev/null || true
	cd rust/xdp-loader && cargo clean 2>/dev/null || true
	rm -f spoof spoof-panel
	rm -rf panel/frontend/.next panel/frontend/out
	rm -rf panel/backend/cmd/panel/web

# ── Help ──
# Prints a quick reminder of the most useful targets.
help:
	@echo "Targets: all, core, panel, test, test-quick, clean"
	@echo "  all        - build core binary + panel (frontend + backend)"
	@echo "  test-quick - fast iteration: Rust tests + Go tests (skips nightly eBPF build)"
	@echo "  clean      - remove all build artifacts"
