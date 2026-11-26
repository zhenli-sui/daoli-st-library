# -*- coding: utf-8 -*-
"""R81 文档增量更新（全部追加式，不重写全文）"""
import io, os, re

LIB = r'C:\Library'
TOTAL, SFT, VER = 1530, 1569, 'v2.73.0'

def rw(p, fn):
    s = io.open(p, encoding='utf-8').read()
    n = fn(s)
    io.open(p, 'w', encoding='utf-8').write(n)
    print('ok', os.path.basename(p), len(s), '->', len(n))

# ---------- README ----------
def readme(s):
    s = s.replace('Total%20Components-1490%20%2F%2010%2C000', 'Total%20Components-1530%20%2F%2010%2C000')
    s = s.replace('SFT%20Corpus-1529%20records', 'SFT%20Corpus-1569%20records')
    s = s.replace('**Total Components: 1,490 / 10,000 (14.9%)**', '**Total Components: 1,530 / 10,000 (15.3%)**')
    s = s.replace('**Version: v2.72.0**', '**Version: v2.73.0**')
    s = s.replace('**SFT 语料: 1529 条**', '**SFT 语料: 1569 条**')
    s = s.replace('**全库约 187,600 行', '**全库约 192,000 行')
    line = ('> **R81（2026-11-24 上午轮 · 冲刺）**：**40 件入册（复杂 4 + 简单 36，5 族模板派生）**——'
            '简单 36：立体库族 8（穿梭车行程/巷道互锁/提升机节拍/盘点差异/横梁倾覆/货位占用/货叉安全/标号校验）·'
            '灌装清洗族 8（抑泡占空比/冲洗水量/消毒保持/电导稀释/喷嘴堵塞/SIP 残留/阀密封磨损/瓶口余量）·'
            '空压站族 7（罐压降/质量分级/干燥剂寿命/电机负载/加载占空/排水间隔/空转率）·'
            '真空吸取族 7（吸盘力/抽吸流量/剥离力/保持衰减/磨损指数/发生器占空/吸盘配置）·'
            '输送传动族 6（线速匹配/链条伸长/辊筒打滑/轮载分配/道岔转角/跟踪偏移）；'
            '复杂 4（RotaryIndexerCycleSeq C5·AsrsSlotAllocSeq C4·FillPreactSelfLearn C4·MeasureInputLatch C3，'
            '均溯源 menes97/ayran-mini-fabrika 与 SRCI_CLIENT_PLC，MIT 绿区）；'
            '总库 1,490→**1,530**，v2.73.0，SFT **1569**。'
            '**L2 闸：首裁 37/40（92.5%）→ 3 件返修（E007 DOWNTO / 双重 LOGIC）→ 终裁 40/40 PASS = 100%，零 EXEMPT**；'
            '审校：批 A 36/36 PASS、零拒收、8 MINOR 挂账；修复件 0（非当日首轮，配额归零）；'
            '开源队列 107→**104 有效（绿 82/黄 22/红 0，净 +12 全绿）**，溯源 4/40 = 10%（未达 30%）。\n'
            '> 今日 **122/300（40.7%）**。\n')
    anchor = '> **R80（2026-11-24 凌晨轮）**'
    i = s.find(anchor)
    assert i > 0
    return s[:i] + line + s[i:]
rw(os.path.join(LIB, 'README.md'), readme)

# ---------- CHANGELOG ----------
def changelog(s):
    add = f"""
## v2.73.0 — 2026-11-24（R81 冲刺轮）

### Added（40 件：复杂 4 + 简单 36）
- **复杂 4**：FB_DL_RotaryIndexerCycleSeq（C5 转盘八工位索引节拍）· FB_DL_AsrsSlotAllocSeq（C4 立库货位分配握手）· FB_DL_FillPreactSelfLearn（C4 灌装预动作量自学习）· FB_DL_MeasureInputLatch（C3 探针测量锁存）
- **简单 36（5 族模板派生）**：立体库族 8 · 灌装清洗族 8 · 空压站族 7 · 真空吸取族 7 · 输送传动族 6

### Fixed（本轮新件返修 3 件，不占存量修复名额）
- FB_DL_RotaryIndexerCycleSeq v1.0.1 — 3 处 `FOR..DOWNTO` 改镜像下标升序（RuSTy E007 编译阻断）
- FB_DL_AsrsSlotAllocSeq v1.0.1 — 补 `diReqSeq<=0` 非法闸（码 36）+ 发布时 ack 快照，消零握手假放行
- FC_DL_BeamToppleRiskChk v1.0.1 — 偏心系数改 `1+|offset|/depth` + 越域闸，消负偏移漏报倾覆风险

### Known Issues（8 MINOR 挂账 R82）
- FC_DL_LaneDiverterAngleCalc：`DL_RAD_TO_DEG := 0.0174533` 名称/单位标签反向（算符为除法故结果正确，唯标签有 3282× 误改风险）
- 6 件死常量（DL_EPS / DL_R_MAX 声明零引用）
- FC_DL_SanitizeHoldTimeCalc：注释与实现顺序不符（代码正确）

### Stats
- 总库 1,490 → **1,530**（DL_Base 196 / DL_MathData 420 / DL_Algo 161 / DL_Device 260 / DL_Motion 143 / DL_Process 350）
- SFT 1,529 → **1,569**；registry ≡ .st（差集 0）；JSONL 高 39 条为 R70 前历史遗留
- L2 闸首裁 92.5% → 终裁 **100%**，零 EXEMPT；开源队列 104 有效（绿 82/黄 22/红 0）
"""
    return s.rstrip() + '\n' + add
rw(os.path.join(LIB, 'CHANGELOG.md'), changelog)

# ---------- VERSION ----------
for d, txt in [('DL_Process', 'v2.73.0  2026-11-24  R81：+27 (复杂 3 + 简单 24)，350 件'),
               ('DL_Device', 'v2.73.0  2026-11-24  R81：+7 (真空吸取族)，260 件'),
               ('DL_Motion', 'v2.73.0  2026-11-24  R81：+7 (输送传动族 6 + MeasureInputLatch)，143 件')]:
    p = os.path.join(LIB, d, 'VERSION')
    if os.path.exists(p):
        io.open(p, 'a', encoding='utf-8').write('\n' + txt + '\n')
        print('ok VERSION', d)

# ---------- ROADMAP ----------
def roadmap(s):
    add = """
## R81 构建轮小结（2026-11-24 上午轮 · 冲刺模式）

> **R81 小结**：**40 件入册**（复杂 4 + 简单 36，5 族模板派生；简单 36 在单次调用内一次写盘，编码耗时 ~9′）。总库 1,490→**1,530**（15.3%），v2.73.0，SFT 1,529→**1,569**。**L2 闸首裁 37/40 = 92.5%**（1×E007 DOWNTO + 2×LOGIC）→ 3 件定点返修 → **终裁 40/40 = 100%，零 EXEMPT**。审校批 A 36/36 PASS、零拒收、0 BLOCK / 0 MAJOR / 8 MINOR；批 B 结论并入 QA_REVIEW_R81_B。修复件 0（非当日首轮，铁律一归零）。开源队列 107→**104 有效（绿 82/黄 22/红 0，净 +12 全绿 MIT）**，溯源 4/40 = 10%（未达 30%，五族垂直工艺在开源 ST 生态确无对应件）。今日 **122/300（40.7%）**。
> **R82 待办（P0）**：① **5 件 R80 逻辑 MAJOR 修复**（SpanCalibRatio 量纲 / AccumulatorSizing 分母 / RefSat R410A 表行 / PneuCvFlow 差压因子 / WeighHopperRefill 复位判据）——顺延至次日首轮，占首轮 4 件配额中的 4 件，第 5 件转 R83；② **`DL_RAD_TO_DEG` 标签反转修正**（全批唯一 3282× 潜在陷阱，含全库 `DL_RAD_TO_DEG` 口径普查）；③ **`FOR..DOWNTO` 全库清剿**（本轮闸席实测 `FC_DL_PolyEvalHorner`、`FB_DL_MarkPositionLatch` 同样 E007，属库级共性缺陷，非个案）；④ 「声明常量零引用」机检落 `dl_gate.py` 锚点（6 件同型噪声）；⑤ 开源换道：清洗球/喷淋覆盖率、SIP 蒸汽灭菌 F0 值、空压站/真空整机 — GitHub 短查询 0 命中，改 clean-room 公式自研路线，不再计入采集 KPI；⑥ 值守三项第 13 轮顺延（GITHUB_TOKEN 真检索 / GATE MAJOR 人核 / L3 向量门）。
"""
    return s.rstrip() + '\n' + add
rw(os.path.join(LIB, 'ROADMAP.md'), roadmap)

# ---------- AGENT_EVOLUTION_LOG ----------
def evolog(s):
    add = """
## R81（2026-11-24 上午轮）

- **[R509] 环境事实 | RuSTy 1.0.8 不支持 `FOR..DOWNTO`（报 E007）| 库内 `FC_DL_PolyEvalHorner`、`FB_DL_MarkPositionLatch` 同样中招，属库级共性缺陷而非个案 | 降序遍历一律改写「镜像下标升序」：`FOR i := 0 TO N-1 DO a[N-i] := a[N-i-1]`，逐拍等价且目标下标恒大于源下标，不可能覆盖。**编码席写盘前须 grep 禁词表 `DOWNTO`**（闸席 R510 同步落锚点）。**
- **[R510] 闸席 | 编译通过但语义错 2 例（带符号偏心致漏报 / 零握手假放行）| L1+L2 双层门禁结构性拦不住"默认引脚值构成的退化路径"——两者都在真实默认值（offset 负数、diReqSeq=0）下才暴露 | 状态机件复核必查「默认引脚组合」：把所有 VAR_INPUT 置零/置默认后走一遍相序，凡能"不经握手/不经判定"直达放行相的即为 BLOCK。**
- **[R511] 编译闸 | 镜像下标移位的等价性需穷举验证，不能靠眼看 | 闸席 20000 例随机穷举失配 0 才放行 | 「结构性改写」类修法必须附逐拍等价性证据（随机穷举或真值表），不接受"看起来对"。**
- **[R512] 总监 | 规划期 token 级撞名扫描把 R81 驳回压到 0（R79 为 22.8%）| 用「≥2 个非通用 token 命中即驳回」的机械判据，比人工语义判断可靠且快 | 撞名三查升级为「token 交集 + 词根饱和统计」双键：先 grep 词根频次挑低饱和域，再 token 交集扫描，两步都不做则族整体放弃。**
- **[R513] 总监 | 5 族垂直工艺（立体库/灌装清洗/空压站/真空/输送）全部零撞名，而通用族（位运算/单位换算/滤波）已饱和 | 1,500 件后简单件产出只能靠「垂直工艺 × 未覆盖设备」挖空白，通用算法族已无增量空间 | 简单件族选择前置一步「词根饱和普查」：任一核心词根在库命中 ≥6 即换域，不硬碰。**
- **[R514] 审校 | 签名指纹去重在 REAL 密集数值 FC 上零判别力（36 件两两相似度天然 0.83~1.00，120 对全假阳性）| 同骨架族件的参数类型序列几乎相同 | 该类族改用「公式核心 + 量纲向量」双键做指纹，类型序列只作辅助。**
- **[R515] 审校 | 6 件同型死常量（DL_EPS / DL_R_MAX 声明零引用），源于模板常量块无差别复制 | 模板派生的副作用：骨架带的常量不一定被用到 | 族模板派生后必跑「声明零引用」机检，命中即删声明，不挂账。**
"""
    return s.rstrip() + '\n' + add
rw(os.path.join(LIB, 'AGENT_EVOLUTION_LOG.md'), evolog)

print('docs done')
