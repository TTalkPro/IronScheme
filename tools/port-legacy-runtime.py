#!/usr/bin/env python3
"""把旧运行时的 C# 文件机械改写到 IronScheme.Core（iron-008 起使用）。用法：python3 tools/port-legacy-runtime.py <源文件> <目标文件>"""
import re, sys

def drop_blocks(src, header_re):
    """删除匹配 header_re 的类声明及其花括号内的全部内容。"""
    while True:
        m = re.search(header_re, src)
        if not m: return src
        i = src.index('{', m.end())
        depth = 0
        for j in range(i, len(src)):
            if src[j] == '{': depth += 1
            elif src[j] == '}':
                depth -= 1
                if depth == 0: break
        # 连同前面的属性行一起删掉
        start = src.rfind('\n', 0, m.start()) + 1
        src = src[:start] + src[j+1:].lstrip('\r\n')

def builtin_to_primitive(m, src):
    args = m.group(1) or ''
    name = re.search(r'"([^"]+)"', args)
    flags = []
    if re.search(r'AllowConstantFold\s*=\s*true', args): flags.append('PrimitiveFlags.Pure')
    if re.search(r'AllowTailCall\s*=\s*true', args): flags.append('PrimitiveFlags.AllowTailCall')
    if name:
        n = name.group(1)
    else:
        # 未写名字：取下一个方法名的小写形式（旧 Generator.AddBuiltins 规则）
        after = src[m.end():]
        mm = re.search(r'static\s+[\w<>\[\],]+\s+(\w+)\s*\(', after)
        n = mm.group(1).lower()
    f = (', Flags = ' + ' | '.join(flags)) if flags else ''
    return f'[Primitive("{n}"{f})]'

def port(src):
    src = src.lstrip('﻿').replace('\r\n', '\n')
    src = drop_blocks(src, r'(static\s+)?partial\s+class\s+BuiltinEmitters\b')
    src = re.sub(r'^using (IronScheme\.Compiler[\w.]*|IronScheme\.Hosting|Microsoft\.Scripting[\w.]*|IronScheme\.Runtime\.R6RS|IronScheme\.Runtime\.psyntax|RuntimeHelpers = [\w.]+);\n', '', src, flags=re.M)
    src = re.sub(r'^namespace IronScheme\.Runtime(\.R6RS)?\b', 'namespace IronScheme.Core', src, flags=re.M)
    out, pos = [], 0
    for m in re.finditer(r'\[Builtin(?:\(([^)]*)\))?\]', src):
        out.append(src[pos:m.start()]); out.append(builtin_to_primitive(m, src)); pos = m.end()
    out.append(src[pos:])
    src = ''.join(out)
    src = src.replace('RuntimeHelpers.Int32ToObject(', 'RT.Box(')
    src = src.replace('Runtime.Cons', 'IronScheme.Core.Cons')
    src = re.sub(r'\bCallable\b', 'Procedure', src)
    # 符号：SymbolTable/SymbolId → Symbol
    src = re.sub(r'SymbolTable\.StringToObject(Fast)?\(', 'Symbol.Intern(', src)
    src = re.sub(r'SymbolTable\.IdToString\(\(SymbolId\)\s*(\w+)\)', r'((Symbol)\1).Name', src)
    src = re.sub(r'SymbolTable\.IdToString\(', 'SymbolName(', src)
    src = re.sub(r'\bSymbolId\b', 'Symbol', src)
    src = re.sub(r'catch \(Continuation\)', 'catch (ContinuationException)', src)
    return src

if __name__ == '__main__':
    data = open(sys.argv[1], 'rb').read()
    try: text = data.decode('utf-8')
    except UnicodeDecodeError: text = data.decode('latin-1')
    open(sys.argv[2], 'w', encoding='utf-8').write(port(text))
