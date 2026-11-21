# -*- coding: utf-8 -*-
"""R21 文档增量（纯追加/定点替换，禁整篇重写）"""
import re, io, os

def rd(p): return io.open(p, encoding='utf-8').read()
def wr(p, s): io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
def rep1(s, old, new, tag):
    assert s.count(old) == 1, (tag, s.count(old))
    return s.replace(old, new)

MATH15 = ['FC_DL_ModPos','FC_DL_DivLrealSafe','FC_DL_QuantizeStep','FC_DL_PolyEvalHorner','FC_DL_WrapAngleDeg',
 'FC_DL_LwordBitFieldExtract','FC_DL_LwordBitFieldInsert','FC_DL_LwordBitCount','FC_DL_Crc16Generic','FC_DL_ChecksumSum8',
 'FC_DL_StringToDint','FC_DL_DwordToHexString','FC_DL_ArraySumLreal','FC_DL_TimeToHmsString','FC_DL_DateToIsoString']
BASE5  = ['FB_DL_MinOnOffGuard','FB_DL_SignalChangeCounter','FB_DL_SamplingTrigger','FB_DL_SignalFrozenDetect','FB_DL_PulseWidthFilter']

def parse(path):
    t = rd(path)
    name = re.search(r'组件名称\s*:\s*(\S+)', t).group(1)
    ver  = re.search(r'当前版本\s*:\s*(\S+)', t).group(1)
    func = ''
    m = re.search(r'功能描述\s*:\s*(.+)', t)
    if m: func = m.group(1).strip().rstrip('。')
    ins, outs = [], []
    cur = None
    for ln in t.splitlines():
        s = ln.strip()
        if s.startswith('VAR_INPUT'): cur = ins; continue
        if s.startswith('VAR_OUTPUT'): cur = outs; continue
        if s.startswith(('VAR_IN_OUT','VAR CONSTANT','VAR')) and not s.startswith('VAR_INPUT'): 
            cur = None; continue
        if s.startswith('END_VAR'): cur = None; continue
        if cur is not None and ':' in s and not s.startswith('//'):
            n = s.split(':')[0].strip()
            if re.match(r'^[A-Za-z_]\w*$', n):
                cur.append(n)
    codes = re.findall(r'16#0001_([0-9A-F]{4})\s*\[(信息|故障)级\]\s*([^，,；;\n]{2,28})', t)
    return name, ver, func, ins, outs, codes

def manual_block(names, cat):
    out = []
    for n in names:
        name, ver, func, ins, outs, codes = parse('C:/Library/%s/%s.st' % (cat, n))
        info = [c for c in codes if c[1] == '信息']
        flt  = [c for c in codes if c[1] == '故障']
        out.append('### `%s`' % name)
        out.append('- **功能**：%s。（v%s，R21 入库）' % (func, ver))
        out.append('- **输入引脚**：%s' % ('、'.join('`%s`' % x for x in ins) if ins else '无（纯约定常量入口）'))
        out.append('- **输出引脚**：%s' % ('、'.join('`%s`' % x for x in outs) if outs else '无'))
        c = []
        if info: c.append('信息 `%s`' % '`/`'.join('16#0001_%s' % x[0] for x in info))
        if flt:  c.append('故障 `%s`' % '`/`'.join('16#0001_%s' % x[0] for x in flt))
        out.append('- **码位**：%s' % (' ｜ '.join(c) if c else '—'))
        out.append('')
    return '\n'.join(out)

def ledger_rows(names, cat):
    out = []
    for n in names:
        name, ver, func, ins, outs, codes = parse('C:/Library/%s/%s.st' % (cat, n))
        for code, lvl, desc in codes:
            out.append('| `16#0001_%s` | %s | %s | `%s` |' % (code, lvl, desc.strip().rstrip('（').strip(), name))
    return '\n'.join(out)

# ---------------- README ----------------
p = 'C:/Library/README.md'; s = rd(p)
s = rep1(s, 'Total%20Components-344%20%2F%2010%2C000', 'Total%20Components-364%20%2F%2010%2C000', 'bd1')
s = rep1(s, 'SFT%20Corpus-344%20records', 'SFT%20Corpus-364%20records', 'bd2')
s = rep1(s, 'Level%200-196%20%2F%2040', 'Level%200-216%20%2F%2040', 'bd3')
s = rep1(s, '> **Total Components: 344 / 10,000** ｜ **Phase 1: 140 / 200（70.0%，2026-11-16 开账）** ｜ **Version: v2.9.0** ｜ **SFT 语料: 344 条** ｜ **全库约 79,956 行**',
         '> **Total Components: 364 / 10,000** ｜ **Phase 1: 178 / 200（89.0%，2026-11-16 开账）** ｜ **Version: v2.10.0** ｜ **SFT 语料: 364 条** ｜ **全库约 82,758 行**', 'stat')
anchor = '；总库 **v2.9.0 / 344 件**，Phase 1 今日 140/200。\n'
block = ('> **Round 21（2026-11-16）：数学安全原子 + LWORD 位域/校验 + 文本序列化 + 守卫 FB 20 件**——DL_MathData 15：批1 数学安全原子 5（`FC_DL_ModPos` 非负取模 / `FC_DL_DivLrealSafe` 除法唯一出口 / `FC_DL_QuantizeStep` 量化步长 / `FC_DL_PolyEvalHorner` Horner 多项式 / `FC_DL_WrapAngleDeg` 角度回绕）、批2 LWORD 位域+校验 5（`FC_DL_LwordBitFieldExtract`/`Insert`、`FC_DL_LwordBitCount` 汉明重、**`FC_DL_Crc16Generic` 参数化 CRC-16 一张实现覆盖任意从站**、`FC_DL_ChecksumSum8` 累加和，挂 T2-1 LGF Bit Logic / Data Handling / Converter 三子族）、批3 文本序列化 5（`FC_DL_StringToDint` 整数字符串严格解析、`FC_DL_DwordToHexString`、`FC_DL_ArraySumLreal`、`FC_DL_TimeToHmsString`、`FC_DL_DateToIsoString` ISO 日期文本 + 回代自校验）；DL_Base 4 批守卫 FB 5（`FB_DL_MinOnOffGuard` 最短运行/停止双守卫、`FB_DL_SignalChangeCounter`、`FB_DL_SamplingTrigger`、`FB_DL_SignalFrozenDetect`、`FB_DL_PulseWidthFilter` 双侧确认脉宽守恒）；合计 **2,802 行**，机检（`_Staging_Raw/2026-11-16/check_r21.py`，嵌套注释判定升级为**非贪婪成对剥离法**）**20/20 PASS fail=0**；registry 344→**364**（v2.10.0，counts 71/145/36/57/25/30），JSONL 364 条全 sha256 MATCH、码位 CLASH=NONE，游标推进至 **信息 `045C` / 故障 `03A8`**；**R21 终审 7 件定向抽查命中 3 件并全部修复**（`FC_DL_DateToIsoString` 年序判据末项除数误用 146097 致 **2000-02-29 等世纪闰日误判 0397 故障**〔严重〕/ `FC_DL_Crc16Generic` 空帧分支漏输出反射〔中等〕/ `FC_DL_PulseWidthFilter` `bReset` 电平清零与引脚注释「上升沿」不符〔轻微〕，另 `FC_DL_StringToDint` 溢出未写 `nErrPos`〔轻微〕一并修，四件升 v1.0.1，对外引脚零变更）；归档 `_Staging_Raw/2026-11-16/BATTLE_REPORT_R21.md`；总库 **v2.10.0 / 364 件**，Phase 1 今日 **178/200（89.0%）**，距 500 冲刺差 **136 件**。\n')
s = rep1(s, anchor, anchor + block, 'r21block')
s = rep1(s, '本库全部 344 件组件', '本库全部 364 件组件', 'vc')
wr(p, s)

# ---------------- CHANGELOG ----------------
p = 'C:/Library/CHANGELOG.md'; s = rd(p)
chg = """## [v2.10.0] — 2026-11-16 ｜ R21 数学安全原子 + LWORD 位域/校验 + 文本序列化 + 守卫 FB 20 件 / Round 21 — Math Safety Atoms, LWORD Bit Fields and Checksums, Text Serialization and Guard FBs

**阶段**：Phase 1 第二十一轮（T0 变体线 + T2-1 LGF 子族 + NE107 语义）｜ **新增组件**：20（`DL_MathData` 15 ｜ `DL_Base` 5，合计 **2,802 行**）｜ **累计**：**364 / 10,000**（全库约 82,758 行）｜ **子库版本**：`DL_MathData` v1.14.0→**v1.15.0**、`DL_Base` v1.14.0→**v1.16.0** ｜ **码位**：信息级至 `045C`、故障级至 `03A8`（全库唯一性求差断言 CLASH=NONE）｜ **终审**：7 件定向抽查，**3 件命中 + 1 件轻微，全部当轮修复**（1 严重 / 1 中等 / 2 轻微，均升 v1.0.1，对外引脚零变更）｜ **红线违规**：0 ｜ **机检**：`check_r21.py` **20/20 PASS fail=0**（嵌套注释判定升级为非贪婪成对剥离法，修正旧正则跨块误报）｜ **JSONL**：**364 条**，全量 sha256 MATCH ｜ **今日入库**：**178 / 200（89.0%）** ｜ **距 500 冲刺**：差 136 件

### 新增 / Added

| 子库 | 组件 | 类型 | 说明 |
|---|---|---|---|
| DL_MathData | `FC_DL_ModPos` / `FC_DL_DivLrealSafe` / `FC_DL_QuantizeStep` / `FC_DL_PolyEvalHorner` / `FC_DL_WrapAngleDeg` | FC×5 | 数学安全原子：非负取模（负数取余三平台不一致，条件加减归一）/ 浮点防御除法唯一出口（溢出用 `|分子|/MAX > |分母|` 等价判据，禁比较已溢出的商）/ 量化步长 / Horner 多项式求值 / 角度回绕（LREAL 精度归约常数） |
| DL_MathData | `FC_DL_LwordBitFieldExtract` / `FC_DL_LwordBitFieldInsert` / `FC_DL_LwordBitCount` | FC×3 | LWORD 64 位域读 / 读改写 / 汉明重计数；移位量一律按容器归一，宽 64 走常量掩码规避超宽移位未定义行为 |
| DL_MathData | `FC_DL_Crc16Generic` | FC×1 | **参数化 CRC-16**：poly / init / xorout / 输入反射 / 输出反射全部引脚化，逐位实现零查表（可移植性优先），反射不用平台专用位反指令；三组公开向量（ARC `BB3D` / CCITT-FALSE `29B1` / XMODEM `31C3`）等价脚本复算命中 |
| DL_MathData | `FC_DL_ChecksumSum8` | FC×1 | 8 位累加和校验，帧长闸 + 拒绝截断 |
| DL_MathData | `FC_DL_StringToDint` | FC×1 | 整数字符串严格解析：四态机 + 首个非法字符位置 + **升位 LINT 累加先判界**（负域上界 `2147483648` 与正域分开写，禁用单侧 ABS 判据）+ `WHILE` 守卫计数 |
| DL_MathData | `FC_DL_DwordToHexString` / `FC_DL_ArraySumLreal` / `FC_DL_TimeToHmsString` / `FC_DL_DateToIsoString` | FC×4 | 文本序列化：DWORD→十六进制文本、LREAL 数组求和（非有限剔除 + 部分和复检）、TIME→`HH:MM:SS`、DATE→`YYYY-MM-DD`（Hinnant 整数算法 + **回代自校验**） |
| DL_Base | `FB_DL_MinOnOffGuard` | FB×1 | 最短运行 / 最短停止双守卫（压缩机、泵、热泵防频繁启停公共原子）；六态机 + `ELSE` 兜底；**`eRunning` 一并纳入最短运行计时**（否则请求撤在运行态会让实际运行时长翻倍），`eIdle` 只看 `bReq`（修正样板死锁形态，见 R92 裁决） |
| DL_Base | `FB_DL_SignalChangeCounter` / `FB_DL_SamplingTrigger` / `FB_DL_SignalFrozenDetect` | FB×3 | 信号变化计数 / 采样触发（节拍注入，不假设扫描周期）/ 信号冻结检测（超时无变化报警） |
| DL_Base | `FB_DL_PulseWidthFilter` | FB×1 | 窄脉冲抑制：**双侧确认窗**（上升沿与下降沿各一只 TON），合格脉宽不失真、输出整体滞后 `tMinWidth`；失能即直通且两只看守同步复位 |

### 修复 / Fixed（R21 终审）

| 组件 | 版本 | 级别 | 缺陷 | 处置 |
|---|---|---|---|---|
| `FC_DL_DateToIsoString` | 1.0.0→1.0.1 | **严重** | 年序判据 `nYoe` 末项除数误用 `DL_ERA_DAYS = 146097`，公开算法此处应为周期内最大天序 `146096`。二者仅在 `nDoe = 146096`（每个 400 年周期最后一天 = 世纪闰日 2 月 29 日）分叉，错值使 `nYoe = 400` 越出 `[0, 399]`，回代自校验随即失败 → **2000-02-29 / 2400-02-29 等合法日期被误判 0397 故障并回退 `'1970-01-01'`** | 新增常量 `DL_ERA_LAST = 146096` 并改用于该式，其余天序取值两除数同解，零副作用；等价脚本复算 5 个向量（含 2000-02-29）全部自校验通过 |
| `FC_DL_Crc16Generic` | 1.0.0→1.0.1 | 中等 | 空帧分支原写 `uInit XOR uXorOut`，未过输出反射，与本件自身段 6 反射口径自相矛盾；在初值为回文（`0000`/`FFFF`）时看不出差异，**非回文初值 + `bReflectOut = TRUE` 的自定义从站参设下必错** | 空帧分支复用 16 次定长反射循环后再异或终值，与主体路径同构 |
| `FB_DL_PulseWidthFilter` | 1.0.0→1.0.1 | 轻微 | `bReset` 引脚注释承诺「上升沿清抑制计数」，主体却写成电平清零；HMI 上按住复位不放时抑制计数被持续压零，现场会误判「一个窄脉冲都没发生」 | 补 `rtReset : R_TRIG` 实例（与其他实例同段无条件刷新）改为沿判定；并把注释里并不存在的「饱和标志」措辞改为实情 |
| `FC_DL_StringToDint` | 1.0.0→1.0.1 | 轻微 | 溢出分支未写 `nErrPos`，导致 `eErr = 038B`（故障级）与 `nErrPos = 0`（「无错」哨兵）并存，诊断自相矛盾 | 溢出位与非法字符位同口径写入 `nErrPos` |

### 变更 / Changed
- 机检脚本 `check_r21.py`：嵌套注释判定由「正则匹配 `(* ... *)`」升级为**非贪婪成对剥离法**（先剥外层再判内层），修正旧正则在跨代码块时把两段独立注释误判为嵌套的假阳性（沉淀规则 R91）。
- 20+1 件头注释统一溯源短语：T0 件「IEC 61131-3 标准语义的道莅防御性实现」、T2 件「道莅 clean-room 防御性实现」；4 处「同上」占位词改写为显式表述（沉淀规则 R92）。

### 编译验证债 / Compile Debt（新增 3 条）
- `FC_DL_TimeToHmsString`：`TIME_TO_DINT` 毫秒口径未实测。
- `FC_DL_DateToIsoString`：`DATE_TO_DINT` 纪元口径（1970-01-01 = 0）未实测，已由回代自校验兜底为可观测故障。
- `FC_DL_LwordBitFieldExtract`：`WORD` 容器 `SHL` 语义（16 位截断 vs 32 位提升）未实测。

---

"""
s = rep1(s, '---\n\n## [v2.9.0] — 2026-11-16', '---\n\n' + chg + '## [v2.9.0] — 2026-11-16', 'chg')
wr(p, s)

# ---------------- 子库 VERSION ----------------
def bump_ver(path, oldv, newv, oldcnt, newcnt, addtxt, section, ledger, tailnote):
    s = rd(path)
    s = rep1(s, '| 子库版本 / Sublibrary Version | **v%s** |' % oldv, '| 子库版本 / Sublibrary Version | **v%s** |' % newv, path)
    s = rep1(s, '| 组件总数 / Components | **%d / 20**' % oldcnt, '| 组件总数 / Components | **%d / 20**' % newcnt, path)
    s = rep1(s, '；R19 之前的计数口径漏计', '；' + addtxt + '；R19 之前的计数口径漏计', path)
    s = rep1(s, '| 库总版本 / Library Version | v2.9.0 |', '| 库总版本 / Library Version | v2.10.0 |', path)
    s = rep1(s, '---\n\n## v1.14.0', section + '---\n\n## v1.14.0', path)
    s = s.rstrip('\n') + '\n\n' + ledger + '\n'
    wr(path, s)

sec_m = """---

## v1.15.0 ｜ 2026-11-16 ｜ R21 数学安全原子 + LWORD 位域/校验 + 文本序列化 15 件 / R21 Math Safety Atoms, LWORD Bit Fields, Checksums and Text Serialization — 15 Components

**批次**：批1 数学安全原子 5 ｜ 批2 LWORD 位域+校验 5（挂 T2-1 LGF Bit Logic / Data Handling / Converter 三子族）｜ 批3 文本序列化 5
**总行数**：本子库本轮 15 件合计 **2,114 行**（全库 20 件 2,802 行）
**机检**：`check_r21.py` 15/15 PASS fail=0（嵌套注释判定升级为非贪婪成对剥离法）
**终审**：本子库抽 5 件，命中 2 件并修复（`FC_DL_DateToIsoString` **严重**·年序除数 146097→146096，`FC_DL_Crc16Generic` 中等·空帧漏输出反射），另 `FC_DL_StringToDint` 轻微修复，三件升 **v1.0.1**，对外引脚零变更
**码位游标（注册表实测）**：信息级推进至 **`045C`** ｜ 故障级推进至 **`03A8`**

| 组件 | 版本 | 类型 | 说明 |
|---|---|---|---|
| `FC_DL_ModPos` | 1.0.0 | FC | 非负取模；负数取余三平台不一致，条件加减归一，零模数闸 |
| `FC_DL_DivLrealSafe` | 1.0.0 | FC | 浮点防御除法唯一出口：微量分母闸 + 非有限闸 + 溢出等价判据 `|分子|/MAX > |分母|`（禁比较已溢出的商） |
| `FC_DL_QuantizeStep` | 1.0.0 | FC | 量化到步长；步长零/负闸，商先判界 |
| `FC_DL_PolyEvalHorner` | 1.0.0 | FC | Horner 多项式求值，系数数组边界检查 |
| `FC_DL_WrapAngleDeg` | 1.0.0 | FC | 角度回绕到 `(-180, 180]`，LREAL 精度归约常数（R51） |
| `FC_DL_LwordBitFieldExtract` | 1.0.0 | FC | LWORD 64 位段提取；移位量归一，宽 64 走常量掩码 |
| `FC_DL_LwordBitFieldInsert` | 1.0.0 | FC | LWORD 位段读改写；先算掩码再读旧值，值真变才计改动 |
| `FC_DL_LwordBitCount` | 1.0.0 | FC | 汉明重计数；定长 64 次循环，无 WHILE |
| `FC_DL_Crc16Generic` | **1.0.1** | FC | **参数化 CRC-16**（poly/init/xorout/入出反射全引脚化）；三组公开向量复算命中；空帧亦过输出反射 |
| `FC_DL_ChecksumSum8` | 1.0.0 | FC | 8 位累加和；帧长超限拒绝不截断 |
| `FC_DL_StringToDint` | **1.0.1** | FC | 整数字符串严格解析：四态机 + 非法位定位 + 升位判界（负域上界分开写）+ 守卫计数 |
| `FC_DL_DwordToHexString` | 1.0.0 | FC | DWORD → 8 位十六进制文本，定宽补零 |
| `FC_DL_ArraySumLreal` | 1.0.0 | FC | LREAL 数组求和；非有限样本剔除 + 部分和复检 |
| `FC_DL_TimeToHmsString` | 1.0.0 | FC | TIME → `HH:MM:SS`；挂 `TIME_TO_DINT` 毫秒口径编译债 |
| `FC_DL_DateToIsoString` | **1.0.1** | FC | DATE → `YYYY-MM-DD`；Hinnant 整数算法 + **回代自校验**；修正年序除数后 2000-02-29 正常输出 |

### 码位台账（R21 新增，本子库 15 件）

| 码位 | 级别 | 语义 | 组件 |
|---|---|---|---|
"""
led_m = ledger_rows(MATH15, 'DL_MathData')
tail_m = """
> 全库码位跨文件重叠 = **0**（`check_r21.py`+注册表正则求差断言 CLASH=NONE 复跑）；本轮信息级 `0434`~`045C`、故障级 `036C`~`03A8` 与 `DL_Base` 共用游标但无交叉占用。
> **游标（注册表实测于 2026-11-16）**：信息级 `045C` ｜ 故障级 `03A8`（下一轮从 `045D` / `03A9` 起分配）。
"""
bump_ver('C:/Library/DL_MathData/VERSION.md', '1.14.0', '1.15.0', 130, 145,
         ' + **R21 数学安全原子/LWORD 位域/文本序列化 15 项**', sec_m, led_m, tail_m)

sec_b = """---

## v1.16.0 ｜ 2026-11-16 ｜ R21 守卫 FB 族 5 件 / R21 Guard Function Blocks — 5 Components

**批次**：批4 守卫 FB（最短运行/停止、信号变化计数、采样触发、信号冻结检测、脉宽抑制）
**总行数**：本子库本轮 5 件合计 **688 行**（全库 20 件 2,802 行）
**机检**：5/5 PASS fail=0
**终审**：本子库抽 2 件（`FB_DL_MinOnOffGuard` / `FB_DL_PulseWidthFilter`），修复 1 件轻微（`bReset` 电平清零与引脚注释「上升沿」不符 → 补 `rtReset` 沿判定）；`MinOnOffGuard` 两处主动偏离**裁定采纳**（详见 `_Staging_Raw/2026-11-16/BATTLE_REPORT_R21.md`）
**码位游标（跨子库共用，注册表实测）**：信息级 **`045C`** ｜ 故障级 **`03A8`**

| 组件 | 版本 | 类型 | 说明 |
|---|---|---|---|
| `FB_DL_MinOnOffGuard` | 1.0.0 | FB | 最短运行/停止双守卫；六态机 + ELSE 兜底；`eRunning` 纳入最短运行计时、`eIdle` 只看 `bReq`（修正样板死锁形态） |
| `FB_DL_SignalChangeCounter` | 1.0.0 | FB | 信号变化计数；饱和锁存 + 复位沿 |
| `FB_DL_SamplingTrigger` | 1.0.0 | FB | 采样触发；节拍由引脚注入，不假设扫描周期 |
| `FB_DL_SignalFrozenDetect` | 1.0.0 | FB | 信号冻结检测；超时无变化置报警 |
| `FB_DL_PulseWidthFilter` | **1.0.1** | FB | 窄脉冲抑制；**双侧确认窗**保证合格脉宽守恒，输出整体滞后 `tMinWidth`；失能直通 |

### 码位台账（R21 新增，本子库 5 件）

| 码位 | 级别 | 语义 | 组件 |
|---|---|---|---|
"""
led_b = ledger_rows(BASE5, 'DL_Base')
tail_b = """
> 全库码位跨文件重叠 = **0**；本轮与 `DL_MathData` 共用 `16#0001_` 段游标但无交叉占用。
> **游标（注册表实测于 2026-11-16）**：信息级 `045C` ｜ 故障级 `03A8`。
"""
bump_ver('C:/Library/DL_Base/VERSION.md', '1.14.0', '1.16.0', 66, 71,
         ' + **R21 守卫 FB 族 5 项**', sec_b, led_b, tail_b)

# ---------------- 手册 ----------------
for mp, names, cat, title in [
    ('C:/Library/DL_MathData/MANUAL_DL_MathData.md', MATH15, 'DL_MathData', 'R21 数学安全原子 / LWORD 位域与校验 / 文本序列化 15 件（v1.15.0 追加）'),
    ('C:/Library/DL_Base/MANUAL_DL_Base.md', BASE5, 'DL_Base', 'R21 守卫 FB 族 5 件（v1.16.0 追加）')]:
    s = rd(mp)
    add = '\n---\n\n## R21 追加接口表 / R21 Interface Tables\n\n> %s。以下引脚表由源码声明区**自动抽取**（`_Staging_Raw/2026-11-16/_r21_doc.py`），不做人工转述，避免文档与代码漂移。\n\n%s\n' % (title, manual_block(names, cat))
    old = "\n\n*Last updated: 2026-11-16（R20 追加接口表）｜ 道莅工控代码库产品总监*"
    assert s.count(old) == 1, mp
    s = s.replace(old, add + "\n*Last updated: 2026-11-16（R21 追加接口表）｜ 道莅工控代码库产品总监*")
    wr(mp, s)

print('DOC-A OK')
