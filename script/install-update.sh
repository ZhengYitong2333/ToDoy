#!/bin/zsh
# Invoked only with a verified candidate prepared by UpdateService.
set -eu
parent_pid="$1"
candidate="$2"
target="$3"
result="$4"
work="${candidate:h}"
replacement="${target:h}/.ToDoy-update-${parent_pid}.app"
backup="${target:h}/.ToDoy-backup-${parent_pid}.app"
replaced=false
finished=false
replacement_owned=false
cleanup() {
  set +e
  if ! $finished; then
    if $replaced && [[ -d "$backup" ]]; then
      rm -rf "$target"
      mv "$backup" "$target"
      /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$target"
      /usr/bin/pluginkit -a "$target/Contents/PlugIns/TodoWidget.appex"
    fi
    mkdir -p "${result:h}"
    print -r -- "更新安装失败，旧版已保留。请重新下载更新或手动安装。" > "$result"
    /usr/bin/open "$target" || true
  fi
  if $replacement_owned; then rm -rf "$replacement"; fi
  rm -rf "$work"
}
trap cleanup EXIT
# Don't replace a running app if quitting was cancelled or reminders are still saving.
for attempt in {1..120}; do
  kill -0 "$parent_pid" 2>/dev/null || break
  sleep 1
done
kill -0 "$parent_pid" 2>/dev/null && exit 1
[[ -d "$candidate" && -d "$target" && ! -e "$backup" && ! -e "$replacement" ]] || exit 1
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$target/Contents/Info.plist")" == local.desktop.todo.panel ]] || exit 1
/usr/bin/codesign --verify --deep --strict "$candidate"
mkdir "$replacement"
replacement_owned=true
/usr/bin/ditto "$candidate" "$replacement"
/usr/bin/codesign --verify --deep --strict "$replacement"
# Keep the old bundle until replacement and launch succeed.
mv "$target" "$backup"
replaced=true
mv "$replacement" "$target"
/usr/bin/codesign --verify --deep --strict "$target"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$lsregister" -u "$backup" >/dev/null 2>&1 || true
"$lsregister" -u "$candidate" >/dev/null 2>&1 || true
"$lsregister" -f "$target"
# The extension uses the old executable until terminated, even after a bundle swap.
/usr/bin/pkill -x TodoWidget || true
/usr/bin/pluginkit -a "$target/Contents/PlugIns/TodoWidget.appex"
/usr/bin/killall NotificationCenter 2>/dev/null || true
/usr/bin/open "$target"
finished=true
rm -rf "$backup"
rm -f "$result"
