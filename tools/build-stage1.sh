#!/bin/sh
# Phase A（iron-028）：在 stage0 上执行文本种子，运行 ironscheme-buildscript-nano.sps，
# 用新编译器把 boot 源文件、nanopass 与编译器编译成 stage1 boot 镜像。
# 用法：tools/build-stage1.sh [输出目录]（默认 IronScheme/IronScheme.Console/build）
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
console="$root/IronScheme/IronScheme.Console"
out=${1:-$console/build}
case "$out" in /*) ;; *) out="$(pwd)/$out" ;; esac
dotnet build "$root/IronScheme/IronSchemeNext.slnx" -c Release -v quiet -nologo > /dev/null
cd "$console"
dotnet ../IronScheme.Stage0/bin/Release/net10.0/stage0.dll -I lib -I lib/nanopass-framework-scheme \
  boot-seed.core ironscheme-buildscript-nano.sps "$out"
