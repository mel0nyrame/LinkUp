#!/usr/bin/env bash
# 用 pubspec 声明的 Flutter 版本执行命令。
#
# 本机共享 SDK 可能比 pubspec 新或旧，`flutter pub get` 会直接失败；
# 这个脚本按声明版本准备一份隔离 SDK，并用 PATH 前置的方式执行命令。
# 共享 SDK 保持原样。
#
#   tool/flutter_sdk.sh flutter test
#   eval "$(tool/flutter_sdk.sh --print-path)" && flutter analyze
#
# 缓存位置可用 LINKUP_FLUTTER_CACHE 覆盖，默认 ~/.cache/linkup-flutter。
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
version=$(sed -n 's/^  flutter: *"\(.*\)"$/\1/p' "$repo_root/pubspec.yaml")
if [ -z "$version" ]; then
  echo "pubspec.yaml 里读不到 environment.flutter" >&2
  exit 1
fi

cache_root=${LINKUP_FLUTTER_CACHE:-$HOME/.cache/linkup-flutter}
sdk_dir="$cache_root/$version/flutter"
archive="$cache_root/flutter_linux_${version}-stable.tar.xz"

if [ ! -x "$sdk_dir/bin/flutter" ]; then
  mkdir -p "$cache_root/$version"
  if [ ! -f "$archive" ]; then
    curl -fsSL -o "$archive.part" \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${version}-stable.tar.xz"
    mv "$archive.part" "$archive"
  fi
  # 先解到临时目录再改名：中断的下载不会留下一个看起来可用、其实残缺的 SDK。
  rm -rf "$cache_root/$version.partial"
  mkdir -p "$cache_root/$version.partial"
  tar -xJf "$archive" -C "$cache_root/$version.partial"
  mv "$cache_root/$version.partial/flutter" "$sdk_dir"
  rm -rf "$cache_root/$version.partial"
fi

if [ "${1:---print-path}" = "--print-path" ]; then
  echo "export PATH=\"$sdk_dir/bin:\$PATH\""
else
  export PATH="$sdk_dir/bin:$PATH"
  exec "$@"
fi
