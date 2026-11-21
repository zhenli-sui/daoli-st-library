for p in ['DL_Algo/VERSION.md','DL_Device/VERSION.md','DL_Motion/VERSION.md','DL_Process/VERSION.md']:
    s=open(p,encoding='utf-8').read()
    a='| 库总版本 / Library Version | v2.2.0 |'
    b='| 库总版本 / Library Version | v2.7.0 |'
    assert a in s, p
    open(p,'w',encoding='utf-8',newline='\n').write(s.replace(a,b,1))
    print('libver',p)
