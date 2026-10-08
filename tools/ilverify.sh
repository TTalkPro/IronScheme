#!/bin/sh
# 用 ILVerify 校验发射器生成的程序集（iron-019）。
# 用法：tools/ilverify.sh <dll> …
# 需要先安装：dotnet tool install -g dotnet-ilverify
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
core="$root/IronScheme/IronScheme.Core/bin/Release/net10.0"
ver=$(dotnet --list-runtimes | grep '^Microsoft.NETCore.App 10\.' | tail -1 | awk '{print $2}')
rtdir=$(dotnet --list-runtimes | grep "^Microsoft.NETCore.App $ver" | sed 's/.*\[\(.*\)\]/\1/')/$ver
ilverify=${ILVERIFY:-$HOME/.dotnet/tools/ilverify}
for dll in "$@"; do
  "$ilverify" "$dll" -r "$rtdir/*.dll" -r "$core/IronScheme.Core.dll" -r "$core/Oyster.IntX.dll"
done
