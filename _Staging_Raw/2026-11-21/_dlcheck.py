import sys, re, os
def check(fp):
    issues=[]
    src=open(fp,encoding='utf-8').read()
    # nested block comments
    d=0; i=0; nested=False
    while i < len(src)-1:
        if src[i]=='(' and src[i+1]=='*':
            d+=1
            if d>1: nested=True
            i+=2; continue
        if src[i]=='*' and src[i+1]==')' and d>0:
            d-=1; i+=2; continue
        i+=1
    if nested: issues.append('嵌套 (* 块注释')
    stripped=re.sub(r'\(\*.*?\*\)','',src,flags=re.S)
    stripped=re.sub(r'//.*','',stripped)
    for pat,label in [(r'\bg_[A-Z]\w*','g_全局'),(r'VAR_EXTERNAL','VAR_EXTERNAL'),(r'%[IQM]\b|%[IQ]X?','物理地址')]:
        for m in re.finditer(pat,stripped):
            ln=stripped[:m.start()].count('\n')+1
            issues.append(f'{label} @L{ln}')
    n_open=len(re.findall(r'^VAR(?:_INPUT|_OUTPUT|_IN_OUT)?\s*$',stripped,re.M))  # VAR CONSTANT 为段内续限定符，不新开 END_VAR（库内既定风格）
    n_close=stripped.count('END_VAR')
    if n_open!=n_close: issues.append(f'VAR/END_VAR 不配对 open={n_open} close={n_close}')
    if 'VAR_OUTPUT' not in src: issues.append('缺 VAR_OUTPUT')
    pairs=[(r'\bFOR\b','END_FOR'),(r'\bWHILE\b','END_WHILE'),(r'\bREPEAT\b','END_REPEAT'),(r'\bCASE\b','END_CASE'),(r'\bIF\b','END_IF'),(r'\bFUNCTION_BLOCK\b','END_FUNCTION_BLOCK')]
    for kop,cname in pairs:
        # strip END_xxx tokens first to avoid IF in nothing; \bIF\b won't match END_IF (underscore word char) so fine
        no=len(re.findall(kop,stripped))
        nc=stripped.count(cname)
        if no!=nc: issues.append(f'{cname} 不配对 open={no} close={nc}')
    # FUNCTION ... END_FUNCTION (exclude FUNCTION_BLOCK)
    no=len(re.findall(r'^FUNCTION\s+\w+',stripped,re.M)); nc=len(re.findall(r'^END_FUNCTION\s*$',stripped,re.M))
    if no!=nc: issues.append(f'FUNCTION/END_FUNCTION 不配对 open={no} close={nc}')
    invar=False
    for i,line in enumerate(src.splitlines(),1):
        s=line.strip()
        if re.match(r'^VAR(_INPUT|_OUTPUT|_IN_OUT| CONSTANT)?$',s): invar=True; continue
        if s=='END_VAR': invar=False; continue
        if invar and s and not s.startswith('//') and s.endswith(';') and ':' in s:
            if '//' not in s: issues.append(f'声明行缺双语注释 @L{i}: {s[:50]}')
    print(f'{os.path.basename(fp)}: ' + ('PASS' if not issues else 'FAIL'))
    for x in issues: print('   -',x)
for fp in sys.argv[1:]: check(fp)
