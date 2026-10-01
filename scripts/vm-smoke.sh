#!/bin/zsh
# Installs the published cask in a throwaway macOS VM, as a new user would get
# it, and checks that it runs; the VM is deleted afterwards.
#
#   scripts/vm-smoke.sh [version]   version: fail unless the cask installs exactly this
#
# Needs the `vm` helper from the dotfiles (tart, TART_HOME) and a base VM,
# gg27 by default (VM_BASE=...). Takes 5–7 minutes.
set -euo pipefail

expected=${${1:-}#v}
base=${VM_BASE:-gg27}
if ! command -v vm >/dev/null; then
    print -u2 "vm-smoke: the vm helper is not on PATH (dotfiles zsh/bin)"
    exit 1
fi

logdir=$(mktemp -d)
trap 'rm -rf "$logdir"' EXIT

# Every step runs under its own alarm: the first launch of a quarantined app
# waits for the "downloaded from the Internet" prompt, and a `tart exec` stuck
# on it never returned. Steps write to a shared file, so a hang still shows
# how far the run got.
vm run "$base" -d "$logdir" -- "
expected='$expected'
log=\"/Volumes/My Shared Files/${logdir:t}/smoke.log\"
failed=0
check() {
    local name=\$1 secs=\$2 want=\$3; shift 3
    local out
    out=\$(perl -e 'alarm shift; exec @ARGV' \"\$secs\" /bin/zsh -c \"\$*\" 2>&1 < /dev/null) || true
    if [[ \$out == *\$want* ]]; then
        print \"ok    \$name\" >> \"\$log\"
    else
        print \"FAIL  \$name: \${out//\$'\n'/ | }\" >> \"\$log\"
        failed=1
    fi
}
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1
print \"macOS \$(sw_vers -productVersion) \$(sw_vers -buildVersion)\" >> \"\$log\"
check 'brew install --cask' 600 'successfully installed' 'brew install --cask servitola/tap/claude-counter'
check 'version' 10 \"\${expected:-.}\" \"/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/ClaudeCounter.app/Contents/Info.plist\"
check 'Gatekeeper: notarized' 30 'source=Notarized Developer ID' 'spctl -a -vv -t exec /Applications/ClaudeCounter.app'
xattr -dr com.apple.quarantine /Applications/ClaudeCounter.app
check 'app launches' 40 'running' 'open /Applications/ClaudeCounter.app; sleep 15; pgrep -x ClaudeCounter >/dev/null && echo running'
check 'widget registered' 20 'com.servitola.claudecounter.widget' 'pluginkit -m -p com.apple.widgetkit-extension'
check 'claude-counter --json' 20 'schemaVersion' 'claude-counter --json'
check 'no crash report' 10 'none' 'ls ~/Library/Logs/DiagnosticReports | grep -i claudecounter || echo none'
check 'brew uninstall --zap' 120 'gone' 'brew uninstall --cask --zap claude-counter >/dev/null 2>&1; test -e /Applications/ClaudeCounter.app || test -e \"\$HOME/Library/Group Containers/NZNV266K59.com.servitola.claudecounter\" || echo gone'
print \"result \$failed\" >> \"\$log\"
" >/dev/null 2>&1 || true

log=$logdir/smoke.log
[[ -f $log ]] || { print -u2 "vm-smoke: the VM produced no log"; exit 1; }
grep -v '^result ' "$log"
grep -q '^result 0$' "$log" || { print -u2 "vm-smoke: FAILED"; exit 1; }
print "vm-smoke: passed"
