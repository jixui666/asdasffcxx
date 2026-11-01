#!/usr/bin/env bash
# 给 uuvpn-*.ipa 做“平台化伪签”，产出可以直接丢给 TrollStore 安装的 ipa。
#
# 为什么需要它：
#   com.apple.mobile.MobileHouseArrest 是系统服务身份，普通开发者/企业证书签出来的
#   App 用它会在启动瞬间被 LaunchServices + 沙盒拒绝（闪退）。TrollStore 的安装方式
#   走平台化签名（platform-application + skip-library-validation），才能既保留这个
#   bundle id，又让 Frameworks/apptrace.framework 这类 dylib 被 dlopen 成功。
#
# 依赖：macOS + ldid（brew install ldid）+ zip/unzip + PlistBuddy（系统自带）
#
# 用法：
#   ./tools/sign-trollstore.sh uuvpn-mha-adhoc.ipa
#   -> 产出 uuvpn-mha-adhoc-trollstore.ipa

set -euo pipefail

IPA="${1:?usage: sign-trollstore.sh <input.ipa> [output.ipa]}"
OUT="${2:-${IPA%.ipa}-trollstore.ipa}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ENT="$HERE/platform.entitlements"

command -v ldid >/dev/null 2>&1 || { echo "ldid not found: brew install ldid"; exit 1; }
[ -f "$ENT" ] || { echo "missing $ENT"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unzip -q "$IPA" -d "$WORK"
APP="$(find "$WORK/Payload" -maxdepth 1 -name '*.app' -print -quit)"
[ -n "$APP" ] || { echo "no Payload/*.app in $IPA"; exit 1; }

executable_of() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$1/Info.plist"
}

sign_one() {
  echo "ldid -S: $1"
  ldid -S"$ENT" "$1"
}

# 1) 独立 dylib
while IFS= read -r -d '' f; do
  sign_one "$f"
done < <(find "$APP" -type f -name '*.dylib' -print0)

# 2) 嵌套 framework / xcframework 切片
while IFS= read -r -d '' fw; do
  exe="$(executable_of "$fw" 2>/dev/null || true)"
  [ -n "${exe:-}" ] && [ -f "$fw/$exe" ] && sign_one "$fw/$exe"
done < <(find "$APP" -type d -name '*.framework' -print0)

# 3) 扩展（先内层后外层）
while IFS= read -r -d '' appex; do
  exe="$(executable_of "$appex")"
  [ -f "$appex/$exe" ] && sign_one "$appex/$exe"
done < <(find "$APP" -type d -name '*.appex' -print0)

# 4) 主程序
MAIN="$(executable_of "$APP")"
sign_one "$APP/$MAIN"

# 5) 去掉 codesign 时代留下的 CodeResources（ldid 不维护它，留着会被校验成不一致）
find "$APP" -type d -name '_CodeSignature' -prune -exec rm -rf {} + 2>/dev/null || true

# 6) 重新打包
rm -f "$OUT"
( cd "$WORK" && zip -qry "$OLDPWD/$OUT" Payload )
ls -lh "$OUT"
echo "done: $OUT  (TrollStore: 分享/文件 App 里点开安装)"
