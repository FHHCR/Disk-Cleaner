#!/usr/bin/env python3
"""PowerShell 语法静态检查器
检查 .ps1 文件的括号/大括号/方括号/引号匹配
PowerShell 规则：
- 单引号字符串 '...': 字面量，'' 表示转义单引号
- 双引号字符串 "...": " 用 `" 转义（反引号），\ 不是转义
- 反引号 ` 是转义字符
用法: python3 ps_check.py <file.ps1>
"""
import sys
import re

def check_ps_syntax(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    errors = []
    stack = []
    pairs = {')': '(', ']': '[', '}': '{'}
    opens = set(pairs.values())
    closes = set(pairs.keys())

    lines = content.split('\n')
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith('#'):
            continue
        in_single = False
        in_double = False
        j = 0
        while j < len(line):
            ch = line[j]
            # PowerShell 转义字符是反引号 `
            if ch == '`' and (in_double or in_single):
                j += 2
                continue
            if ch == "'" and not in_double:
                # 单引号转义：'' 表示字面单引号
                if in_single and j + 1 < len(line) and line[j+1] == "'":
                    j += 2
                    continue
                in_single = not in_single
            elif ch == '"' and not in_single:
                in_double = not in_double
            elif not in_single and not in_double:
                if ch in opens:
                    stack.append((ch, i))
                elif ch in closes:
                    if stack and stack[-1][0] == pairs[ch]:
                        stack.pop()
                    else:
                        errors.append(f"Line {i}: unexpected '{ch}'")
            j += 1
        if in_single:
            errors.append(f"Line {i}: unclosed single quote")
        if in_double:
            errors.append(f"Line {i}: unclosed double quote")

    for ch, line in stack:
        errors.append(f"Line {line}: unclosed '{ch}'")

    funcs = re.findall(r'function\s+([\w-]+)', content)
    return errors, funcs

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 ps_check.py <file.ps1>")
        sys.exit(1)
    errors, funcs = check_ps_syntax(sys.argv[1])
    if errors:
        print(f"ERRORS in {sys.argv[1]}:")
        for e in errors:
            print(f"  {e}")
        sys.exit(1)
    else:
        print(f"SYNTAX OK: {sys.argv[1]}")
        if funcs:
            print(f"  Functions: {', '.join(funcs)}")
