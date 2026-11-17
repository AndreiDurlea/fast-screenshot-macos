#!/bin/zsh
# scripts/build-app.sh             release build into build/FastScreenshot.app
# scripts/build-app.sh --install   build, copy to /Applications and open it
set -euo pipefail

cd "${0:A:h}/.."

label=com.durlea.fastscreenshot
app=build/FastScreenshot.app

swift build -c release
bin="$(swift build -c release --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin/FastScreenshot" "$app/Contents/MacOS/FastScreenshot"
sed "s/VERSION_PLACEHOLDER/$(cat VERSION)/g" Resources/Info.plist > "$app/Contents/Info.plist"

# An ad hoc signature's designated requirement is its code hash, which changes with every build,
# so macOS would drop the Accessibility grant each time. Pinning it to the bundle identifier keeps it.
codesign --force --sign - --identifier "$label" -r="designated => identifier \"$label\"" "$app" >/dev/null
echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
  # Earlier versions ran as com.durlea.fast-screenshot from ~/Applications and as an SMAppService agent.
  launchctl bootout "gui/$(id -u)/com.durlea.fast-screenshot" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/com.durlea.fast-screenshot.plist"
  rm -rf "$HOME/Applications/FastScreenshot.app" "$HOME/.local/bin/fast-screenshot"
  launchctl bootout "gui/$(id -u)/$label.agent" 2>/dev/null || true

  # The installed copy runs as a LaunchAgent with KeepAlive, so stop the job before replacing it.
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  pkill -x FastScreenshot 2>/dev/null || true
  rm -rf /Applications/FastScreenshot.app
  cp -R "$app" /Applications/FastScreenshot.app
  open /Applications/FastScreenshot.app
  echo "Installed /Applications/FastScreenshot.app"
fi
