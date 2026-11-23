#!/bin/zsh
set -eu
cd "${0:A:h:h}"
app="/Applications/ToDoy.app"
package_mode=false
if [[ "${1:-}" == "--package" ]]; then
  [[ -n "${2:-}" ]] || { print -u2 "Usage: $0 --package output-directory"; exit 1; }
  package_mode=true
  package_output="${2:A}"
fi
identity="${TODO_SIGN_IDENTITY:--}"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
stage=$(mktemp -d)
bundle="$stage/ToDoy.app"
packaged_bundle=""
cleanup() {
  # Running a bundle self-check can register the temporary app with LaunchServices.
  # A newer build outside /Applications can then invalidate the installed widget.
  "$lsregister" -u "$bundle" >/dev/null 2>&1 || true
  if [[ -n "$packaged_bundle" ]]; then
    "$lsregister" -u "$packaged_bundle" >/dev/null 2>&1 || true
  fi
  rm -rf "$stage"
  if [[ -d "$app" ]]; then
    "$lsregister" -f "$app" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
# Retire only this project's packaging copies; keep all artifacts and task data.
for artifact in dist/**/ToDoy.app(N/); do
  if [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$artifact/Contents/Info.plist" 2>/dev/null)" == local.desktop.todo.panel ]]; then
    "$lsregister" -u "$artifact" >/dev/null 2>&1 || true
  fi
done
mkdir -p "$bundle/Contents/"{MacOS,Resources}
swiftc -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk -target arm64-apple-macos15.0 main.swift Store.swift Views.swift Backgrounds.swift QuickEntry.swift CompletionBurst.swift Todo.swift Reminders.swift TaskScheduleViews.swift ScheduleChecks.swift -o "$bundle/Contents/MacOS/DesktopTodo"
if $package_mode; then
  swiftc -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk -target x86_64-apple-macos15.0 main.swift Store.swift Views.swift Backgrounds.swift QuickEntry.swift CompletionBurst.swift Todo.swift Reminders.swift TaskScheduleViews.swift ScheduleChecks.swift -o "$stage/DesktopTodo-intel"
  lipo -create "$bundle/Contents/MacOS/DesktopTodo" "$stage/DesktopTodo-intel" -output "$stage/DesktopTodo-universal"
  cp "$stage/DesktopTodo-universal" "$bundle/Contents/MacOS/DesktopTodo"
fi
cp Info.plist "$bundle/Contents/"
cp Resources/Backgrounds/* "$bundle/Contents/Resources/"
cp Resources/Complete.wav "$bundle/Contents/Resources/"
sips -s format jpeg -Z 1600 '/System/Library/Desktop Pictures/Sonoma.heic' --out "$bundle/Contents/Resources/Landscape.jpg" >/dev/null
ext="$bundle/Contents/PlugIns/TodoWidget.appex"
mkdir -p "$ext/Contents/MacOS" "$stage/Todo.iconset"
swiftc -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk -target arm64-apple-macos15.0 -application-extension -parse-as-library -Xlinker -e -Xlinker _NSExtensionMain Widget/Widget.swift Todo.swift -o "$ext/Contents/MacOS/TodoWidget"
if $package_mode; then
  swiftc -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk -target x86_64-apple-macos15.0 -application-extension -parse-as-library -Xlinker -e -Xlinker _NSExtensionMain Widget/Widget.swift Todo.swift -o "$stage/TodoWidget-intel"
  lipo -create "$ext/Contents/MacOS/TodoWidget" "$stage/TodoWidget-intel" -output "$stage/TodoWidget-universal"
  cp "$stage/TodoWidget-universal" "$ext/Contents/MacOS/TodoWidget"
fi
cp Widget/Info.plist "$ext/Contents/"
# WidgetKit validates each timeline against the installed host and extension build.
build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' Info.plist)
[[ "$build" == <-> ]] || exit 1
if [[ -f "$app/Contents/Info.plist" ]]; then
  previous=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Contents/Info.plist")
  [[ "$previous" == <-> ]] || exit 1
  if (( previous >= build )); then
    build=$((previous + 1))
  fi
fi
for info in "$ext/Contents/Info.plist" "$bundle/Contents/Info.plist"; do
  plutil -replace CFBundleVersion -string "$build" "$info"
done
codesign --force --sign "$identity" --entitlements Widget/Entitlements.plist "$ext"
swift script/icon.swift "$stage/icon.png"
for size in 16 32 128 256 512; do
  for scale in 1 2; do
    suffix=""
    [[ $scale == 2 ]] && suffix="@2x"
    sips -z $((size*scale)) $((size*scale)) "$stage/icon.png" --out "$stage/Todo.iconset/icon_${size}x${size}${suffix}.png" >/dev/null
  done
done
iconutil -c icns "$stage/Todo.iconset" -o "$bundle/Contents/Resources/Todo.icns"
codesign --force --sign "$identity" "$bundle"
"$bundle/Contents/MacOS/DesktopTodo" --self-check
if $package_mode; then
  codesign --verify --deep --strict "$bundle"
  mkdir -p "$package_output"
  [[ ! -e "$package_output/ToDoy.app" ]] || { print -u2 "Output app already exists"; exit 1; }
  ditto "$bundle" "$package_output/ToDoy.app"
  packaged_bundle="$package_output/ToDoy.app"
  print "Packaged $package_output/ToDoy.app"
  exit 0
fi
legacy="/Applications/桌面待办.app"
if [[ ! -e "$app" && -d "$legacy" && "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$legacy/Contents/Info.plist")" == local.desktop.todo.panel ]]; then
  mv "$legacy" "$app"
fi
if [[ -d "$app" ]]; then
  [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist")" == local.desktop.todo.panel ]] || exit 1
  pkill -x DesktopTodo || true
fi
# A process from before the app was renamed may still serve obsolete timelines.
for installed in "$app" "$legacy"; do
  pkill -f "^$installed/Contents/PlugIns/TodoWidget[.]appex/Contents/MacOS/TodoWidget( |$)" || true
done
ditto "$bundle" "$app"
codesign --verify --deep --strict "$app"
"$lsregister" -u "$bundle" >/dev/null 2>&1 || true
"$lsregister" -f "$app"
# Chronod may relaunch the old extension while the bundle is being copied.
# Stop it again only after the complete bundle and host registration are current.
pkill -f "^$app/Contents/PlugIns/TodoWidget[.]appex/Contents/MacOS/TodoWidget( |$)" || true
pluginkit -a "$app/Contents/PlugIns/TodoWidget.appex"
# The renderer can retain the previous bundle's placeholder even after a
# successful timeline reload. Restart it after installation, preserving layout.
killall NotificationCenter 2>/dev/null || true
open "$app"

link="$HOME/Desktop/ToDoy.app"
oldlink="$HOME/Desktop/桌面待办.app"
if [[ ! -e "$link" && ! -L "$link" ]]; then
  ln -s "$app" "$link"
fi
if [[ -L "$oldlink" && "$(readlink "$oldlink")" == "$legacy" && "$(readlink "$link")" == "$app" ]]; then
  unlink "$oldlink"
fi
