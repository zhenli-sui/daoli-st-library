# -*- coding: utf-8 -*-
"""把云端看板从 v1 五席结构升级到 v2 七席（S0 主控 + S1~S6）并刷新数据。
用法: python patch_dashboard_v2.py <work_dir>/index.html
只改文本与 DATA 块，不触碰任何 pnid 锚点。
"""
import io
import sys

P = sys.argv[1]
t = io.open(P, encoding="utf-8").read()
orig_len = len(t)

NEW_DATA = r'''const DATA = {
  cats:[
    {k:"DL_MathData", n:"数学与数据处理", c:454, col:"#22d3ee", kids:[["字符/字符串族",68],["单位换算族",64],["对齐取整族",42],["统计滤波族",55],["BCD/位运算族",48],["限幅爬坡族",52],["其他算法族",125]]},
    {k:"DL_Process", n:"过程控制", c:610, col:"#34d399", kids:[["温度/换热控制",96],["泵阀逻辑",78],["批次/配方序列",88],["PID/串级",58],["联锁保护",62],["萃取/烧结工艺",40],["其他",188]]},
    {k:"DL_Device", n:"设备控制", c:352, col:"#a78bfa", kids:[["电机/变频",74],["传感器诊断",66],["执行机构",60],["通讯协议栈",50],["其他",102]]},
    {k:"DL_Base", n:"基础类型与工具", c:233, col:"#3b82f6", kids:[["位运算/字节序",54],["奇偶校验",34],["时间/定时",40],["字符串工具",42],["保温/热工计算",10],["其他",53]]},
    {k:"DL_Algo", n:"核心算法", c:197, col:"#fbbf24", kids:[["滤波/估计",50],["插值/拟合",42],["状态机框架",34],["搜索/排序",26],["其他",45]]},
    {k:"DL_Motion", n:"运动控制", c:195, col:"#f472b6", kids:[["定位/点动",48],["张力/卷绕",42],["凸轮/电子齿轮",28],["纠偏/EPC",10],["其他",67]]}
  ],
  cmplx:[["C1",214,"#22d3ee"],["C2",690,"#22d3ee"],["C3",397,"#a78bfa"],["C4",284,"#a78bfa"],["C5",190,"#a78bfa"],["C6",131,"#f472b6"],["C7",75,"#f472b6"],["C8",38,"#f87171"],["C9",22,"#f87171"]],
  rounds:[["R88",39,"11-25"],["R89",39,"11-25"],["R90",40,"11-25"],["R91",60,"11-25"],["R92",40,"11-25"],["R93",39,"11-25"],["R94",40,"11-25"]],
  stages:[
    {ic:"🗺️",nm:"S1 规划查重",ag:"dlf-planner（原生 · 已实测）",st:"ok",stt:"R94 T+15′ 落盘 · 40 件",d:"上承 S0 配额，下交 S3。读注册表/路线图/源矩阵 → 40 条目标表（族模板连号、词根饱和度查重、磁盘差集前置），产出 ROUND_PLAN 即本席唯一交付"},
    {ic:"🕸️",nm:"S2 开源供料",ag:"dlf-sourcer（原生 · 按需触发）",st:"ok",stt:"队列 289 行 / 有效 273 · 本轮未触发",d:"由「每轮必跑」改为「按需」：队列有效 <30 才采集，平时优先消耗 213 条绿区存量。通道已 401/404/配额三重故障，避免每轮白烧 12~18 分钟网络 IO"},
    {ic:"⌨️",nm:"S3 编码",ag:"dlf-builder（原生）",st:"ok",stt:"40 件 / 4,629 行 · 1 次调用",d:"按 S1 计划序号 1→N 顺序写盘；族模板批量派生（4 族 × 10 件）；R1~R16 红线自检；只写不裁，编译结论权归 S4"},
    {ic:"🚦",nm:"S4 编译闸",ag:"dlf-gatekeeper（原生 · 已实测）",st:"ok",stt:"首裁 39/40 → 复裁 40/40 · 零豁免",d:"一票否决。串行 jobs=1 逐件裁决（并发会凭空造出 E004 假阳性）；缓存命中不算新验证，复裁必须 --no-cache；自检实测抓出 FB_DL_BiquadCascade.st E059 真缺陷"},
    {ic:"🔍",nm:"S5 审校去重",ag:"dlf-inspector（原生）",st:"ok",stt:"全量 40 件 · BLOCK 0 · 拒收 0",d:"12 项扫查（逐项给行号证据）+ 代数值回代 + 三道去重（名称/签名/语义）；防误杀：同族位宽、REAL/LREAL 精度、协议方言属有效变体"},
    {ic:"🔧",nm:"S6 定点修复",ag:"dlf-fixer（原生 · 已实测）",st:"ok",stt:"R94 MAJOR 3 件全部定点闭环",d:"只按 S4 FAIL 单 / S5 缺陷清单逐行定点修，最小干预、禁整文件重写、改后必重走出口赋值序列；不自裁 PASS、不顺手优化清单外代码。成立理由：主控自修自裁在 R92 引入 2 处新缺陷"},
    {ic:"📦",nm:"S0 注册入库",ag:"dlf-lead（主控）",st:"ok",stt:"2,041 / 2,080 / 2,041",d:"仅 S4 PASS 且 S5 PASS 的件写 INDEX_REGISTRY + JSONL 单行 + 勾 ROADMAP；三方对账（registry 条数 = JSONL 行数 ≈ .st 文件数）"},
    {ic:"📄",nm:"S0 文档战报",ag:"dlf-lead（主控）",st:"ok",stt:"追加式增量 ✔ · 战报 ≤100 行",d:"README 徽章 / CHANGELOG / ROADMAP / AGENT_EVOLUTION_LOG / DAILY_RETRO / BATTLE_REPORT，全部追加式，严禁整篇重写"},
    {ic:"📡",nm:"S0 飞书播报",ag:"lark-cli bot",st:"ok",stt:"已送达战报群",d:"看板 + 分档 + L2 通过率 + CI 结论 + 队列 + 复盘瓶颈 + 风险一句话 → 代码战报群（严禁私聊创始人）"}
  ],
  experts:[
    {name:"dlf-lead（S0 主控）",zh:"工厂主控 · 产品总监",role:"S0 · 配额派工、终审、入库、文档、复盘（不写代码、不裁编译）",ic:"🎯",col:"#22d3ee",path:"C:\\Users\\Administrator\\.workbuddy\\plugins\\cache\\my-experts\\daoli-lib-factory\\2.0.0\\agents\\dlf-lead.md",ledger:"DIRECTOR_EVOLUTION.md",stats:"R94 当日 316/300 达标（105.3%）· 全库 2,041/10,000",
     desc:"产线调度者，不是主力程序员。负责盘点、分配 40 件配额（复杂 ≤12 / 简单 ≥28）、按 S1→S6 顺序派工、按 S4/S5 裁决执行入库或隔离、写战报与复盘。两条硬约束：不亲自动手改业务代码（改由 S6），不用自己的预筛结果冒充 S4 的正式裁决。"},
    {name:"dlf-planner（S1）",zh:"规划查重官",role:"S1 · 40 件目标规划表 + 词根饱和度查重 + 磁盘差集前置",ic:"🗺️",col:"#38bdf8",path:"C:\\Users\\Administrator\\.workbuddy\\plugins\\cache\\my-experts\\daoli-lib-factory\\2.0.0\\agents\\dlf-planner.md",ledger:"DIRECTOR_EVOLUTION.md · 规划线",stats:"连通性自检通过（本尊已读自身规范 + 依赖文件）· R94 规划 T+15′",
     desc:"把「今天该造什么」变成一张可执行清单。核心动作：按族模板成族规划（同族 6~10 件连号）、撞名四查（名称/签名/语义邻件/词根饱和度）、磁盘差集前置避免重写已存在文件。不写代码，只交 ROUND_PLAN_R<轮>.md。"},
    {name:"dlf-sourcer（S2）",zh:"开源供料官",role:"S2 · 按需采集 + 许可证分级 + 候选队列维护",ic:"🕸️",col:"#34d399",path:"C:\\Users\\Administrator\\.workbuddy\\plugins\\cache\\my-experts\\daoli-lib-factory\\2.0.0\\agents\\dlf-sourcer.md",ledger:"OSS_HUNTER_EVOLUTION.md",stats:"队列 289 行 / 有效 273（绿 213 / 黄 60 / 红 0）· 通道枯竭已立案",
     desc:"只供料不写码。按需触发：队列有效 <30 条才外出采集，否则优先消耗存量。许可证铁律：绿区（MIT/Apache/BSD/MPL/ISC）可参考并标注；黄区（EPL/OSCAT/WTFPL）只借语义；红区（GPL/AGPL/LGPL）只读思想，一行代码不进队列。"},
    {name:"dlf-builder（S3）",zh:"PLC 编码专家",role:"S3 · 按序号顺序写盘 + R1~R16 红线自检",ic:"⌨️",col:"#fbbf24",path:"C:\\Users\\Administrator\\.workbuddy\\plugins\\cache\\my-experts\\daoli-lib-factory\\2.0.0\\agents\\dlf-builder.md",ledger:"PLC_EXPERT_EVOLUTION.md",stats:"R94 一次调用写 40 件 / 4,629 行 · T+18 完成",
     desc:"产线唯一写业务代码的席位。纪律：族模板批量派生（严禁一件一调用）、零占位符、16 条红线（零 GVL/零物理地址/纯跨平台语法/防除零越界/双语注释/ENUM+CASE+ELSE、METHOD 声明顺序、显式类型转换、VAR 分号、禁 PROPERTY、禁 VLA 透传、引用前确认 PASS）。写只写，判不判由 S4。"},
    {name:"dlf-gatekeeper（S4）",zh:"编译闸门官",role:"S4 · L1/L2 逐件裁决 · 一票否决 · 独立于编码",ic:"🚦",col:"#f87171",path:"C:\\Users\\Administrator\\.workbuddy\\plugins\\cache\\my-experts\\daoli-lib-factory\\2.0.0\\agents\\dlf-gatekeeper.md",ledger:"COMPILE_VERIFIER_EVOLUTION.md",stats:"自检实测：AbsEx PASS、BiquadCascade E059 FAIL 识别准确 · 缓存 PASS 不采信，强制 --no-cache 复裁",
     desc:"唯一有否决权的席位。双层门禁：L1 静态门（tree-sitter + 红线 + 声明引用交叉核对）FAIL 即阻断；L2 真编译门（本地 RuSTy 串行 / 云端 MatIEC）FAIL 即回派 S6。铁律：缓存命中不算验证；同一错误码连续 3 轮豁免必须升 P0 根治。"},
    {name:"dlf-inspector（S5）",zh:"审校与去重官",role:"S5 · 12 项扫查 + 三道去重 · 与 S1 不同源",ic:"🔍",col:"#a78bfa",path:"C:\\Users\\Administrator\\.workbuddy\\plugins\\cache\\my-experts\\daoli-lib-factory\\2.0.0\\agents\\dlf-inspector.md",ledger:"QA_DEDUP_EVOLUTION.md",stats:"R94 全量 40 件 BLOCK 0 / MAJOR 3 全闭环 / 拒收 0",
     desc:"管「能不能发、和别人重不重」，不参与规划以避免自审。12 项定向扫查逐项给行号证据，禁写「整体看起来没问题」；语义重复件拒收必须指明与哪一件重复。防误杀：同族不同阶、精度变体、协议方言属有效变体。"},
    {name:"dlf-fixer（S6）",zh:"定点修复官",role:"S6 · 只按缺陷单逐行定点修，不自裁 PASS",ic:"🔧",col:"#fb923c",path:"C:\\Users\\Administrator\\.workbuddy\\plugins\\cache\\my-experts\\daoli-lib-factory\\2.0.0\\agents\\dlf-fixer.md",ledger:"PLC_EXPERT_EVOLUTION.md · 修复线",stats:"连通性自检通过（自身规范 52 行 + 编码规范 384 行均读取成功）",
     desc:"从主控身上拆出来的独立席位，成立依据是 R92 事故：主控自己修、自己判，结果复裁抓出 2 处修复引入的新缺陷。只收 S4 的 FAIL 单和 S5 的缺陷清单，逐行最小干预，禁整文件重写，改完必须重走出口赋值序列，然后交回 S4/S5 独立复裁。"}
  ],
  rules:[
    ["R1","零 GVL / VAR_EXTERNAL"],["R2","零 %I/%Q 物理地址"],["R3","纯 IEC 61131-3 跨平台语法"],["R4","防除零/越界/浮点容差"],
    ["R5","变量中英双语注释"],["R6","状态机 ENUM+CASE+ELSE 兜底"],["R7","TON/R_TRIG 无条件周期刷新"],["R8","METHOD 先声明后实现"],
    ["R9","每个 METHOD 必有 END_METHOD"],["R10","禁构造函数式转换（用 X_TO_Y）"],["R11","VAR 声明必须分号结尾"],["R12","ENUM 成员 := 赋值"],
    ["R13","编码前语义查重+邻件声明"],["R14","FB 内禁用 PROPERTY"],["R15","禁 VLA→VLA 透传"],["R16","引用他件须已 PASS 否则内联"],
    ["R17","数组下标禁 LREAL（E059）"],["R18","缓存 PASS 不算验证，复裁 --no-cache"]
  ],
  ledgers:[
    ["PLC_EXPERT_EVOLUTION","S3 编码 + S6 修复","R789","重复声明扫全声明名 / 冻结须使能保持 / 跨拍状态随撤销清零"],
    ["DIRECTOR_EVOLUTION","S0 主控 + S1 规划","R789","词根饱和度查重 / P0 只带 2 项 / 回归非裁决须标注"],
    ["OSS_HUNTER_EVOLUTION","S2 开源供料","R789","通道枯竭取证 / MIT 洗白识别 / codeload 整包改造"],
    ["COMPILE_VERIFIER_EVOLUTION","S4 编译闸","R789","扫描器须自证 / 缓存 PASS 不算验证 / L1 不可替代 L2"],
    ["QA_DEDUP_EVOLUTION","S5 审校去重","R789","代数值回代法 / 承诺语义一致性 / 跨拍状态生命周期"]
  ],
  bottles:[
    ["R92","主控自修自裁：复裁抓出主控修复引入的 2 处新缺陷（占当轮 MAJOR 2/3）","已根治：修复从主控拆成 S6 独立席位，修复与裁决彻底分属两个 ID，主控不再改业务代码"],
    ["R94","供料通道枯竭：净增 0（目标 ≥8），search 401 + 点名仓 404 + contents API 配额打穿","已改按需触发：队列有效 <30 才采集，优先消耗 213 条绿区存量，不再每轮白烧网络 IO"],
    ["R94","规划耗时占 43% 墙钟（15′/35′）","已拆出 S1 规划席单独承载，主控只做终审；词根检索下一步脚本固化"]
  ],
  todos:[
    ["P0","FB_DL_BiquadCascade.st E059（LREAL 作数组下标）→ S6 定点修复 + --no-cache 复裁（S4 自检实抓）"],
    ["P0","供料通道改造：codeload 整包 + 二进制工程解包；修 oss_harvest.py 三缺陷"],
    ["P1","库内 9 组重名 ENUM 清账（挂账第 6 轮）"],
    ["P1","累计 279 件推送 + 远端 main 的 rebase（R93 卡在 ff 拒绝）"],
    ["P1","REAL_TO_UDINT(x*1000) 无上限钳位全库扩面"],
    ["P2","dlf-planner 第 0 步要求读 README 全文（26k tokens 超限）→ 规范改为分段读"]
  ],
  today:[["R91",40,"10:23 → 10:52","29′","简单 36 + 复杂 4 · L2 40/40 · 当日 158"],["R92",40,"12:55 → 14:30","95′","简单 36 + 复杂 4 · 复裁抓出修复引入 2 处新缺陷 · 当日 198"],["R93",39,"15:43 → 16:28","45′","简单 35 + 复杂 4 · 拒收 1（真重复）· 当日 237"],["R94",40,"18:26 → 19:05","39′","简单 34 + 复杂 6 · 首裁 39P/1F → 复裁 40P · 当日 316/300 达标"],["R94",40,"19:05 收尾","—","任务暂停待架构评审 · 全库 2,041 / SFT 语料 2,080 行"]],
  ticker:["FB_DL_ReMixerSettlerSeq · 混合澄清槽串级（R94）","FC_DL_ReStripAcidDosageCalc · 反萃酸耗三段单位链（R94）","FB_DL_CathodeKilnZoneSeq · 辊道窑多温区（R94）","FC_DL_CathodeO2PartialPressureCalc · 氧分压换算（R94）","FB_DL_WebGuideEpcSeq · EPC 纠偏闭环（R94）","FC_DL_WebSlitWidthCalc · 分切条数与边料（R94）","FC_DL_InsulationThicknessCalc · 反求保温厚度（R94）","FB_DL_HeatTraceCtrlSeq · 电伴热温控（R94）"]
};'''

# 1) 整体替换 DATA 块
s = t.find("const DATA = {")
e = t.find("\n};", s)
if s < 0 or e < 0:
    raise SystemExit("未找到 DATA 块")
t = t[:s] + NEW_DATA + t[e + 3:]

# 2) 文案：五席 -> 七席
REPL = [
    ("五席账本 · 连续 60+ 轮零兜底", "七席账本 · S1/S4/S6 已实测原生召唤"),
    ("五步生命周期产线（五席专家流水线 · 点击节点查看席位详情）",
     "七席产线（S0 主控 + S1~S6 专席 · 点击节点查看席位详情）"),
    ("专家团编制（daoli-lib-factory 五席 · 缺任一席不得入库）",
     "专家团编制（daoli-lib-factory v2.0.0 七席 · 缺 S3/S4/S5 不得入库）"),
    ("五席进化账本（_EXPERT_EVOLUTION · 每轮各追加 ≤5 条，游标 R490）",
     "五本进化账本（_EXPERT_EVOLUTION · 七席共用，每轮各追加 ≤5 条）"),
    ("四个成员席位每轮强制原生召唤（subagent），",
     "六个专业席位由主控按 S1→S6 顺序派工（规划 / 供料 / 编码 / 编译闸 / 审校 / 修复），2026-11-25 22:56 实测 S1/S4/S6 原生召唤成功，团队包 v2.0.0 已生效、无需重启；"),
    ("🟢 绿点 = 本轮该席位原生召唤成功（连续 60+ 轮零兜底）",
     "🟢 绿点 = 该席位原生召唤成功（v2.0.0 已实测 S1 规划 / S4 闸 / S6 修复三席）"),
    ("⚡ 编码 / 采集 / 审校三席并行，编译闸 jobs=1 串行保真",
     "⚡ S2 供料按需触发；S3 写盘后可预排下一批，S4 裁决串行 jobs=1 保真"),
    ("道莅工业代码库工厂 · 云端权威版（唯一维护入口，本地副本仅作草稿）· 数据截至 2026-11-25 19:05 · 数据源 INDEX_REGISTRY.json（2041 件 / 今日 316）· R94 已完成（当日 316/300，105.3%）· SFT 语料 2080 行",
     "道莅工业代码库工厂 · v2.0.0 七席架构 · 云端权威版（唯一维护入口，本地副本仅作草稿）· 数据截至 2026-11-25 22:56 · 数据源 INDEX_REGISTRY.json（2,041 件 / 今日 316，达标 105.3%）· SFT 语料 2,080 行 · 团队包已实测生效，无需重启"),
]
miss = []
for a, b in REPL:
    if a in t:
        t = t.replace(a, b)
    else:
        miss.append(a[:26])

io.open(P, "w", encoding="utf-8").write(t)
print("原长度:", orig_len, "-> 新长度:", len(t))
print("未命中:", miss if miss else "无（全部替换成功）")
# 校验 pnid 锚点未损
import re
print("pnid 锚点数:", len(re.findall(r"<!--pnid:", t)))
print("data-page-node-id 数:", len(re.findall(r"data-page-node-id=", t)))
