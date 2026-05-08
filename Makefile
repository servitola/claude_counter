.PHONY: build release install update reinstall uninstall run kill clean check setup-cert verify-sign

# Local dev build (debug, no install).
build:
	cd App && swift build

release:
	cd App && swift build -c release

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

check: build
