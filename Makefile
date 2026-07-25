.PHONY: build release install update ship reinstall uninstall purge run kill clean check setup-cert verify-sign \
        test lint lint-fix format format-check dead-code analyze ci hooks-install release-notarized

# Developer ID identity + notarytool keychain profile used for official builds.
# Override on the command line if either changes, e.g.
#   make release-notarized NOTARY_PROFILE=other-profile
DEVID          ?= Developer ID Application: Vladislav Konovalov (NZNV266K59)
NOTARY_PROFILE ?= claude-counter-notary

# ----- Build & deploy ---------------------------------------------------------

# Local dev build (debug, no install).
build:
	cd App && swift build

release:
	cd App && swift build -c release

# Official build: Developer ID signature + hardened runtime, notarized by
# Apple and stapled, producing ClaudeCounter-<version>.zip for a release.
# One-time setup of the notary profile (stores credentials in the keychain):
#   xcrun notarytool store-credentials "$(NOTARY_PROFILE)" \
#     --apple-id <your-apple-id> --team-id NZNV266K59 --password <app-specific-password>
release-notarized:
	CODESIGN_IDENTITY="$(DEVID)" NOTARY_PROFILE="$(NOTARY_PROFILE)" \
		./scripts/build-app.sh --notarize

# One-time: create a stable self-signed code-signing cert.
# Without this, every rebuild = new identity = TCC permissions and the
# Login Item registration get reset by macOS. Run once per machine.
setup-cert:
	./scripts/setup-codesign-cert.sh

# Install fresh into /Applications. Stops any running instance first,
# replaces the bundle, then relaunches it if it was running.
install:
	./scripts/build-app.sh --install

# Build + install + ALWAYS relaunch. Use this for "deploy a new version".
update:
	./scripts/build-app.sh --update

# Build, install, relaunch, then nuke every untracked / build artifact in
# the working tree. The .app in /Applications keeps running on its own —
# the repo only needs sources and configs to rebuild later.
# Frees ~212 MB (the SwiftPM .build directory).
ship: update
	git clean -dfx

# Force a clean reinstall: nuke the existing bundle then install.
reinstall:
	-pkill -x ClaudeCounter
	rm -rf /Applications/ClaudeCounter.app
	./scripts/build-app.sh --update

uninstall:
	-pkill -x ClaudeCounter
	rm -rf /Applications/ClaudeCounter.app
	@echo "Uninstalled. Persistent data still in:"
	@echo "  ~/Library/WebKit/com.servitola.claudecounter/  (login cookies)"
	@echo "  ~/Library/Preferences/com.servitola.claudecounter.plist"
	@echo "Run 'make purge' to remove those too."

purge: uninstall
	rm -rf "$(HOME)/Library/WebKit/com.servitola.claudecounter"
	rm -f  "$(HOME)/Library/Preferences/com.servitola.claudecounter.plist"
	defaults delete com.servitola.claudecounter 2>/dev/null || true

# Confirm /Applications/ClaudeCounter.app is signed with the stable cert.
verify-sign:
	@codesign -dv --verbose=4 /Applications/ClaudeCounter.app 2>&1 \
		| grep -E '(Identifier|Authority|TeamIdentifier|Hash type|CDHash)'

kill:
	-pkill -x ClaudeCounter

# Quick alias: build, install, run.
run: update

clean:
	cd App && swift package clean
	rm -rf App/.build/ClaudeCounter.app

# ----- Quality gates ----------------------------------------------------------

# Tests run from the package root.
test:
	cd App && swift test

# SwiftLint with --strict so warnings fail the build.
lint:
	swiftlint lint --strict --config .swiftlint.yml

# Auto-fix what SwiftLint can. The rest must be fixed by hand.
lint-fix:
	swiftlint lint --fix --config .swiftlint.yml

# SwiftFormat — rewrite files in place.
format:
	swiftformat App/Sources App/Tests --config .swiftformat

# CI-safe: error if anything would be reformatted.
format-check:
	swiftformat App/Sources App/Tests --config .swiftformat --lint

# Static dead-code analysis. --strict turns warnings into a non-zero exit.
# Periphery resolves the config path against `--project-root`, so we
# pass an absolute path to keep .periphery.yml at the repo root.
dead-code:
	periphery scan --project-root App --config "$(CURDIR)/.periphery.yml" --strict

# Heavy analyzer rules (capture_variable, unused_declaration, etc.).
# Requires a finished build, hence the dependency.
analyze: build
	swiftlint analyze --strict --config .swiftlint.yml \
		--compiler-log-path App/.build/debug.yaml || true

# Everything CI runs. Order is the cheapest-first so failures surface fast.
check: format-check lint test dead-code

ci: check

# ----- Pre-commit hook --------------------------------------------------------

# Installs `pre-commit` git hook (defined in .pre-commit-config.yaml).
hooks-install:
	pre-commit install --install-hooks
	@echo "Pre-commit hook installed. Run 'pre-commit run --all-files' to test."
