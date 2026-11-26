# -*- coding: utf-8 -*-
"""R86 进化账本：QA 撞号重编 + 四席教训追加"""
import io, os, re

ROOT = r'C:\Library\_EXPERT_EVOLUTION'


def remap_qa():
    p = os.path.join(ROOT, 'QA_DEDUP_EVOLUTION.md')
    s = open(p, encoding='utf-8').read()
    lines = s.split('\n')
    mapping = {'R597': 'R610', 'R598': 'R611', 'R599': 'R612', 'R600': 'R613', 'R601': 'R614'}
    n = 0
    for i, ln in enumerate(lines):
        if '[R86]' in ln:
            for old, new in mapping.items():
                if ln.rstrip().endswith('| ' + old):
                    lines[i] = ln.rstrip()[:-len(old)] + new
                    n += 1
                    break
    open(p, 'w', encoding='utf-8').write('\n'.join(lines))
    return n


def append(name, text):
    with open(os.path.join(ROOT, name), 'a', encoding='utf-8') as f:
        f.write(text)


ren = remap_qa()
print('QA renumbered:', ren)

append('DIRECTOR_EVOLUTION.md', """
## R86（2026-11-24 当日末轮）新增 5 条
- [R86] 治理 | `settings.json` 里 `daoli-lib-factory@my-experts` 与五席单包全部 `true`，但实际只有 `dlf-oss-hunter` 可召唤；`dlf-plc-coder` / `dlf-compile-verifier` / `dlf-qa-dedup` 三席均报 `Task agent ... is not available`，被迫走原名回退 | **`enabledPlugins=true` ≠ agent 已注册生效**，团队包需重启 WorkBuddy 才全席注册；开轮前应先用一次空探测确认席位可用性，而不是在编码关键路径上才发现 | R615
- [R86] 产能 | 当日 278（7 轮）→ **317/300（105.7%）首次达标**；本轮 40 件目标 39 件入库（拒收 1），单席一次调用 8 分钟写盘 40 件 / 3,035 行 | 「一席一次调用写整批」的单位成本约 12 秒/件，远优于一件一调用；族模板 + 连号是产能的真正来源 | R616
- [R86] 差集 | 磁盘差集前置在规划第 2 件就拦下 2 个已存在名（`FC_DL_AccelUnitConvert` / `FC_DL_TimeUnitConvert`），若按关键词脑补「单位换算还没做全」会直接覆盖在册件 | 「某族还没做」的判断必须来自 registry+磁盘双向差集，不能来自关键词命中的直觉 | R617
- [R86] 质量 | 审校本轮全量 40 件（不抽样）报 1 BLOCK + 1 MAJOR + 10 MINOR，主控逐条复核后 **2/2 成立、零误判**（对照 R85 误判率 25%）；拒收 1 件经核实为真重复 | 「BLOCK 必附源码原文行」一条硬约束，一轮就把审校误判率从 25% 压到 0%，应固化为常设条款 | R618
- [R86] 决策 | 317/300 的达成归因于「当日 8 轮×40」，而非单轮产能相对 R72~R74 有本质变化 | 300/日 与 3h/轮 的匹配关系应改写为「每日 ≥8 轮」；某日轮次 <8 则结构性不达标，与铁律执行无关 | R619
""")

append('PLC_EXPERT_EVOLUTION.md', """
## R86（2026-11-24 当日末轮）新增 3 条
- [R86] 语法 | 40/40 件 L2 首次全过（连续第 9 轮零豁免）；`FOR..DOWNTO` 新件命中 0（主控预筛唯一命中为文件头注释误报） | 红线进派单模板后新件零复发，证明「模板级约束」优于「事后扫查」 | R620
- [R86] 实现 | Q15 定点族 9 件统一「DINT 中间域 + 出口饱和」两段式；`FC_DL_Q15MulSat` 先判溢出条件再除 32768 | 定点族必须先约定「中间域宽度」再落码，否则逐件各自决定会产生不可移植的隐式回绕 | R621
- [R86] 实现 | `FB_DL_Q15BiquadFilter` 受 R16 约束不得调用同轮的 `FC_DL_Q15MulSat`，改为 FB 内自写定点乘加 | 同轮成族的件必须默认「兄弟件不可用」，自包含是默认而非例外 | R622
""")

append('COMPILE_VERIFIER_EVOLUTION.md', """
## R86（2026-11-24 当日末轮）新增 3 条
- [R86] 方法 | 40 件按单件绝对路径串行调用（Python 列表驱动），约 90 秒跑完，PASS 40/40 | R604 的做法第 2 次复用即稳定，批量参数（`--sample`/`--round`/目录）应彻底从日常流程移除 | R623
- [R86] 对照 | 负向对照命中 E006 / E007 / E048 三类，证明闸能 FAIL | 100% 通过率必须附对照才可上报（R605 固化后首次复用，流程已跑通） | R624
- [R86] 观察 | 主控预筛 grep `DOWNTO` 命中 1 处，实为文件头「禁用 `FOR..DOWNTO`」的注释说明，属假缺陷 | 文本机检必须剔除注释行，否则会把红线声明本身当成违规 | R625
""")

append('OSS_HUNTER_EVOLUTION.md', """
## R86（2026-11-24 当日末轮）新增 2 条
- [R86] 采集 | 队列 225 条（绿 163 / 黄 62 / 红 0），净 +10，全部 Apache-2.0 支撑件；本轮四族（Q15 定点 / 量程映射 / 饱和算术 / 单位换算）开源命中 **0** | 连续第 5 轮实证：底层数值方法与垂直工艺族在开源 PLC 生态中系统性空白，「溯源 30%」对该类族不可达，需拆双 KPI | R626
- [R86] 合规 | `Ben-Bergh/homeassistant-tcp-modbus` 的 GitHub API `license` 字段判绿，落地读 LICENSE 全文实为 **AGPL-3.0**，已删下载包 | 许可证判定必须读仓内 LICENSE 全文，API 的 license 字段只能作初筛，不能作结论 | R627
""")

# 游标
open(os.path.join(ROOT, '_cursor.txt'), 'w', encoding='utf-8').write(
    '# 全局规则编号游标：下一个可分配 = R628（R86 收口）\n'
    '# R86 已分配：QA R610-R614（原 R597-R601 撞号重编，第 4 次撞号事故） / DIRECTOR R615-R619\n'
    '#           PLC R620-R622 / COMPILE R623-R625 / OSS R626-R627\n'
    '# 校验方式：开轮第一步 grep 各账本实测最大号，不信本文件；同轮只允许一席起号\n')
print('cursor -> R628')
print('total new rules = 20')
