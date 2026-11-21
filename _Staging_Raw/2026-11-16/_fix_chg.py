p='CHANGELOG.md'
s=open(p,encoding='utf-8').read()
a='`DL_Algo` v1.9.0→**v1.10.0**、`DL_Device` v0.8.0→**v0.9.0**、`DL_Motion` v1.1.0→**v1.2.0**、`DL_Process` v1.4.0→**v1.5.0**'
b='`DL_Algo` v1.7.0→**v1.8.0**、`DL_Device` v0.9.0→**v0.10.0**、`DL_Motion` v0.9.0→**v0.10.0**、`DL_Process` v0.9.0→**v0.10.0**'
assert a in s
open(p,'w',encoding='utf-8',newline='\n').write(s.replace(a,b,1))
print('changelog version line aligned')
