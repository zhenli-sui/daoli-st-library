import io
p='SOURCE_HUNTING_MATRIX.md'
s=open(p,encoding='utf-8').read()
subs=[
 ('| T2-1 LGF · Bit Logic | ◐ |','| T2-1 LGF · Bit Logic | ◐ R18 深化 |'),
 ('| T2-1 LGF · Data Handling | ◐ |','| T2-1 LGF · Data Handling | ◐ R18 深化 |'),
 ('| T2-1 LGF · Math | ◐ |','| T2-1 LGF · Math | ◐ R18 深化 |'),
 ('| T2-1 LGF · Measurement | ◐ |','| T2-1 LGF · Measurement | ◐ R18 深化 |'),
 ('| T2-5 Mod_PID_Control | ◐ |','| T2-5 Mod_PID_Control | ◐ R18 深化 |'),
 ('| T2-6 Rockwell AOI | ◐ |','| T2-6 Rockwell AOI | ◐ R18 深化 |'),
 ('| T2-7 PackML / OMAC | ◐ |','| T2-7 PackML / OMAC | ◐ R18 深化 |'),
 ('| T2-8 ISA-88 / ISA-18.2 / NE107 | ◐ |','| T2-8 ISA-88 / ISA-18.2 / NE107 | ◐ R18 深化 |'),
 ('| T1-6 PLCopen Motion | ◐ |','| T1-6 PLCopen Motion | ◐ R18 深化 |'),
]
n=0
for a,b in subs:
    if a in s:
        s=s.replace(a,b,1); n+=1
    else:
        print('MISS:',a[:40])
open(p,'w',encoding='utf-8',newline='\n').write(s)
print('matrix updated rows:',n)
