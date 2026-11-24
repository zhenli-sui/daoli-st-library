import re, sys, os, io

def load(path):
    with open(path, 'r', encoding='utf-8') as f:
        return f.read()

def strip_comments(src):
    # remove (* *) blocks (non-nested per standard) and // tails
    out = []
    i = 0
    n = len(src)
    while i < n:
        if src.startswith('(*', i):
            j = src.find('*)', i + 2)
            if j < 0:
                out.append(' ' * (n - i))
                break
            out.append(re.sub(r'[^\n]', ' ', src[i:j+2]))
            i = j + 2
        elif src.startswith('//', i):
            j = src.find('\n', i)
            if j < 0:
                out.append(' ' * (n - i))
                break
            out.append(' ' * (j - i))
            i = j
        else:
            out.append(src[i])
            i += 1
    return ''.join(out)

def check(path):
    src = load(path)
    code = strip_comments(src)
    errs = []
    warns = []

    # 1 banned words (whole file incl. comments)
    for w in ['同上', '同前', '见上', 'ditto', 'idem', 'TODO', '待补充', '省略', '...']:
        if w in src:
            errs.append('BANNED-WORD %s' % w)
    # 2 global / external / physical address
    if re.search(r'\bg_[A-Za-z]', code):
        errs.append('GLOBAL g_ reference')
    if 'VAR_EXTERNAL' in code.upper():
        errs.append('VAR_EXTERNAL present')
    if re.search(r'%[IQMX]', code):
        errs.append('physical address %I/%Q')
    # 3 code bits (event codes use the XXXX_XXXX grouped form; plain masks are allowed)
    if re.search(r'16#[0-9A-Fa-f]{4}_[0-9A-Fa-f]{4}', code):
        errs.append('hardcoded 16# event code bit')
    # 4 enum single colon
    for m in re.finditer(r'^\s+([A-Za-z_]\w*)\s*:\s*-?\d', code, re.M):
        errs.append('ENUM single colon: %s' % m.group(0).strip())
    # 5 declaration lines without // comment
    in_decl = False
    for lineno, line in enumerate(src.split('\n'), 1):
        s = line.strip()
        if re.match(r'^(VAR|VAR_INPUT|VAR_OUTPUT|VAR_IN_OUT|VAR CONSTANT|VAR_TEMP|VAR_GLOBAL)\b', s):
            in_decl = True
            continue
        if re.match(r'^END_VAR\b', s):
            in_decl = False
            continue
        if in_decl and s and not s.startswith('//'):
            # declaration line: contains ':' and ';'
            if (';' in s or s.endswith(',')) and ':' in s:
                if '//' not in line:
                    errs.append('DECL no inline comment L%d: %s' % (lineno, s[:70]))
                # initial value check
                if ':=' not in s and 'VAR_IN_OUT' not in s:
                    warns.append('DECL no initial value L%d: %s' % (lineno, s[:60]))
    # 6 literal zero divisors and constant terms
    for pat in [r'/\s*0(?![\dxX.])', r'TO_LREAL\(\s*0\s*\)', r'TO_REAL\(\s*0\s*\)', r'OR\s+TRUE', r'AND\s+FALSE']:
        if re.search(pat, code):
            errs.append('SUSPECT literal zero/constant term: %s' % pat)
    # 7 CASE must have ELSE
    if re.search(r'\bCASE\b', code) and not re.search(r'\bELSE\b', code):
        errs.append('CASE without ELSE')
    # 8 timer/trig instances must be called at column 0
    insts = re.findall(r'^\s+(\w+)\s*:\s*(TON|TOF|TP|R_TRIG|F_TRIG|CTU|CTD|CTUD)\s*;', code, re.M)
    for name, typ in insts:
        for m in re.finditer(r'([ \t]*)' + re.escape(name) + r'\s*\(', code):
            indent = m.group(1)
            if indent != '':
                errs.append('TIMER/TRIG %s called with indentation (inside a branch?)' % name)
                break
        if not re.search(re.escape(name) + r'\s*\(', code):
            errs.append('TIMER/TRIG %s never called' % name)
    # 9 undeclared underscore identifiers
    decl = set()
    for m in re.finditer(r'^\s+(\w+)\s*:\s*', code, re.M):
        decl.add(m.group(1).upper())
    for m in re.finditer(r'\b(_[A-Za-z]\w*)\b', code):
        name = m.group(1)
        if name.upper() not in decl:
            errs.append('UNDECLARED %s' % name)
            break
    # 10 balance
    for a, b, tag in [('(', ')', 'paren'), ('[', ']', 'bracket')]:
        if code.count(a) != code.count(b):
            errs.append('UNBALANCED %s %d/%d' % (tag, code.count(a), code.count(b)))
    for kw in ['IF', 'CASE', 'WHILE', 'FOR', 'REPEAT']:
        pass
    if len(re.findall(r'\bIF\b', code)) != len(re.findall(r'\bEND_IF\b', code)):
        errs.append('IF/END_IF mismatch %d/%d' % (len(re.findall(r'\bIF\b', code)), len(re.findall(r'\bEND_IF\b', code))))
    if len(re.findall(r'\bCASE\b', code)) != len(re.findall(r'\bEND_CASE\b', code)):
        errs.append('CASE/END_CASE mismatch')
    if len(re.findall(r'\bWHILE\b', code)) != len(re.findall(r'\bEND_WHILE\b', code)):
        errs.append('WHILE/END_WHILE mismatch')
    if len(re.findall(r'\bFOR\b', code)) != len(re.findall(r'\bEND_FOR\b', code)):
        errs.append('FOR/END_FOR mismatch')
    # 11 function-block / function terminator
    if re.search(r'FUNCTION_BLOCK\s+\w+', code) and 'END_FUNCTION_BLOCK' not in code:
        warns.append('FUNCTION_BLOCK without END_FUNCTION_BLOCK')
    if re.search(r'^FUNCTION\s+\w', code, re.M) and 'END_FUNCTION' not in code:
        warns.append('FUNCTION without END_FUNCTION')
    if 'END_TYPE' not in code and 'TYPE ' in code:
        warns.append('TYPE without END_TYPE')
    # 12 'AS' cast / C-style casts
    if re.search(r'\bAS\s+(INT|DINT|REAL|LREAL|WORD|BOOL)\b', code):
        errs.append('dialect AS cast')
    for m in re.finditer(r'(?<![_A-Za-z0-9])(DINT|INT|REAL|LREAL|WORD|BOOL|UDINT)\s*\(', code):
        # allow the declaration "name : TYPE" and known std funcs
        prev = code[max(0, m.start()-1):m.start()]
        if prev not in (':', ' '):
            errs.append('C-style cast: %s' % m.group(0))
    # 13 float equality
    for m in re.finditer(r'\b([A-Za-z_]\w*)\s*(=|<>)\s*([A-Za-z_]\w*|\d)', code):
        line = code[:m.start()].count('\n') + 1
        warns.append('possible float equality L%d: %s' % (line, m.group(0)))
    return errs, warns

if __name__ == '__main__':
    for p in sys.argv[1:]:
        errs, warns = check(p)
        print('=== %s' % os.path.basename(p))
        for e in errs:
            print('  FAIL %s' % e)
        for w in warns[:12]:
            print('  warn %s' % w)
        print('  lines=%d errs=%d warns=%d' % (len(load(p).split('\n')), len(errs), len(warns)))
