# -*- coding: utf-8 -*-
"""R79 收口：registry 注册 + SFT 语料追加（支撑脚本，数据由 _r79_accept.json 驱动）

用法：
  python _tools/r77_closeout.py --dry            # 只报告，不写盘
  python _tools/r77_closeout.py                  # 正式写盘（先自动备份）
输入：C:\\Library\\_Staging_Raw\\2026-11-23\\_r79_accept.json
  [{"name":"FC_DL_X","category":"DL_Base","type":"FC","complexity":1,
    "tags":["a","b"],"origin":"自研（字符串族模板派生）","license":"MIT"}, ...]
"""
import json, os, io, re, sys, shutil, datetime

LIB = r'C:\Library'
REG = os.path.join(LIB, 'INDEX_REGISTRY.json')
JSONL = os.path.join(LIB, '_AI_Training_Dataset', 'daoli_st_sft_dataset.jsonl')
STAGE = os.path.join(LIB, '_Staging_Raw', '2026-11-24')
ACCEPT = os.path.join(STAGE, '_r79_accept.json')
NOW = '2026-11-24T03:55:00+08:00'
VERSION = '2.71.0'
DRY = '--dry' in sys.argv


def read(p):
    with open(p, encoding='utf-8') as f:
        return f.read()


def grab(src, tag):
    """抽取文件头某字段段落（到下一个 ' ：' 字段为止）。"""
    m = re.search(r'\*\s*' + tag + r'[^:：]*[:：](.*?)(?=\n\s*\*\s*[^\n]{0,24}[:：])', src, re.S)
    if not m:
        return ''
    txt = re.sub(r'^\s*\*\s?', '', m.group(1), flags=re.M)
    return ' '.join(txt.split())


def build_item(it):
    p = os.path.join(LIB, it['category'], it['name'] + '.st')
    if not os.path.exists(p):
        raise SystemExit('缺源文件: ' + p)
    src = read(p)
    func = grab(src, '功能描述') or grab(src, '功能')
    bnd = grab(src, '边界')
    iface = grab(src, '接口')
    scope = grab(src, '分工声明')
    domain = {'DL_Base': '基础运算/字符串与位处理', 'DL_MathData': '数学与数据换算',
              'DL_Algo': '算法与信号处理', 'DL_Device': '设备驱动与诊断',
              'DL_Motion': '运动控制', 'DL_Process': '工艺过程控制'}.get(it['category'], '工业控制')
    instr = ('在%s类项目的 %s 场景中，需要实现 %s 组件：%s'
             % (domain, it['tags'][0] if it['tags'] else domain, it['name'], func[:600]))
    if bnd:
        instr += ' 边界与约束：' + bnd[:900]
    instr += ' 请用 IEC 61131-3 结构化文本实现，要求零全局变量、零厂商私有库、含完整变量双语注释与安全预置。'
    arch = []
    arch.append('【接口与分工】%s %s' % (iface[:500], ('分工：' + scope[:300]) if scope else ''))
    arch.append('【结构设计】按 IEC 61131-3 %s 组织：VAR_INPUT 入参 / VAR_OUTPUT 出参 / VAR 内部状态 / VAR CONSTANT 常量系数；'
                '出口在段 0 预置安全值（返回 FALSE + 哨兵 0 + 最严错误码），随后按域闸逐段早退，保证任何非法输入都不产生不确定输出。'
                % it['type'])
    arch.append('【防错设计】%s' % (bnd[:700] if bnd else '分母先判零、下标钳位、非有限值双判（NaN 自反 / Inf 差自减）、浮点容差 1E-9。'))
    arch.append('【可测性】文件头内置验收向量（≥3 条），覆盖正常路径、边界钳位与故障路径；纯函数无副作用，FB 状态机含 ELSE 兜底态。')
    return {
        'instruction': re.sub(r'\s+', ' ', instr).strip(),
        'architecture_thought': '\n'.join(arch),
        'output': src,
        'meta': {'name': it['name'], 'category': it['category'], 'version': '1.0.0', 'round': 'R77'}
    }


def main():
    items = json.load(open(ACCEPT, encoding='utf-8'))
    reg = json.load(open(REG, encoding='utf-8'))
    have = {c['name'] for c in reg['components']}
    new = [it for it in items if it['name'] not in have]
    dup = [it['name'] for it in items if it['name'] in have]
    print('accept=%d  新增=%d  已在册=%d %s' % (len(items), len(new), len(dup), dup[:5]))
    built = [build_item(it) for it in new]
    bad = [b['meta']['name'] for b in built if len(b['output']) < 800 or 'END_' not in b['output']]
    print('语料自检：源文件过短或缺 END_ 的件 =', bad)
    regrows = []
    for it in new:
        regrows.append({
            'name': it['name'], 'category': it['category'], 'type': it['type'],
            'file_path': os.path.join(LIB, it['category'], it['name'] + '.st'),
            'function_tags': it['tags'], 'complexity': it['complexity'],
            'registered_at': NOW,
            'origin': {'mode': 'internal', 'source': it.get('origin', '道莅原创（自研线）'),
                       'license': it.get('license', 'MIT'), 'ref_tag': it['tags'][0] if it['tags'] else 'std'},
            'l2_status': 'l2-pass'
        })
    cnt = dict(reg['counts'])
    for r in regrows:
        cnt[r['category']] = cnt.get(r['category'], 0) + 1
    print('counts 新=', cnt, 'sum=', sum(cnt.values()), 'expect', len(reg['components']) + len(new))
    if DRY:
        print('DRY：不写盘。示例语料 instruction 前 200 字：')
        print(built[0]['instruction'][:200] if built else '(空)')
        return
    ts = datetime.datetime.now().strftime('%H%M%S')
    shutil.copy2(REG, os.path.join(STAGE, 'INDEX_REGISTRY.bak_r79_%s.json' % ts))
    shutil.copy2(JSONL, os.path.join(STAGE, 'jsonl.bak_r79_%s.jsonl' % ts))
    reg['components'].extend(regrows)
    reg['counts'] = cnt
    reg['total_components'] = len(reg['components'])
    reg['version'] = VERSION
    reg['last_updated'] = NOW
    assert sum(cnt.values()) == reg['total_components'], 'counts sum 断言失败'
    json.dump(reg, open(REG, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    with open(JSONL, 'a', encoding='utf-8') as f:
        for b in built:
            f.write(json.dumps(b, ensure_ascii=False) + '\n')
    n_st = sum(1 for root, _d, fs in os.walk(LIB) for x in fs
               if x.endswith('.st') and 'DL_' in root and '_Staging' not in root and '_tools' not in root)
    print('WROTE registry=%d counts=%s jsonl_+%d' % (reg['total_components'], cnt, len(built)))
    print('三数核对：registry=%d  jsonl=%d  st=%d' % (
        reg['total_components'],
        sum(1 for _ in open(JSONL, encoding='utf-8')),
        n_st))


if __name__ == '__main__':
    main()
