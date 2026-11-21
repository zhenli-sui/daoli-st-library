import io
fixes = [
 ('DL_Algo/VERSION.md', '| 组件总数 / Components | **28**（FB 22 ｜ FC 6） |', '| 组件总数 / Components | **32**（FB 26 ｜ FC 6） |'),
 ('DL_Device/VERSION.md', '| 组件总数 / Components | **50**（接口 18 ｜ 功能块 32） |', '| 组件总数 / Components | **53**（接口 19 ｜ 功能块 34） |'),
 ('DL_Motion/VERSION.md', '| 组件总数 / Components | **18**（接口 1 ｜ 功能块 16 ｜ 函数 1） |', '| 组件总数 / Components | **21**（接口 1 ｜ 功能块 19 ｜ 函数 1） |'),
 ('DL_Process/VERSION.md', '| 组件总数 / Components | **26**（功能块 26） |', '| 组件总数 / Components | **28**（功能块 28） |'),
]
for p, a, b in fixes:
    s = open(p, encoding='utf-8').read()
    assert a in s, p
    open(p, 'w', encoding='utf-8', newline='\n').write(s.replace(a, b, 1))
    print('fixed', p)
