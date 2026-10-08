#!/bin/sh
# 用旧系统快照（legacy-stage0/）生成文本种子 IronScheme/IronScheme.Console/boot-seed.core（iron-015）。
# 旧系统会优先加载当前目录和脚本所在目录下的 psyntax/*.sls 源码，所以把脚本复制到临时目录、在快照目录下运行，
# 源码根目录作为参数传入。
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
console="$root/IronScheme/IronScheme.Console"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$console/seed-buildscript.sps" "$tmp/"
cd "$root/legacy-stage0"
DOTNET_ROLL_FORWARD=Major dotnet IronScheme.ConsoleCore.dll "$tmp/seed-buildscript.sps" "$console/" < /dev/null
