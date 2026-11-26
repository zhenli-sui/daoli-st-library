import json, os, datetime
added = json.load(open(r'C:\Library\_Staging_Raw\2026-11-25\r89_added.json', encoding='utf-8'))
disk = {}
import glob
for p in glob.glob(r'C:\Library\DL_*\*.st'):
    disk[os.path.basename(p)[:-3]] = p

APP = r'C:\Library\_AI_Training_Dataset\daoli_st_sft_dataset.jsonl'
n_before = sum(1 for _ in open(APP, encoding='utf-8'))

def instr(name, cat, fn):
    return (f"某{cat.replace('DL_','')}工段需要把「{fn}」做成控制器里可直接复用的标准件（{name}）。"
            f"现场约束：① 所有配置参数与模拟量输入都可能出现 NaN/INF 或超量程，必须逐项入闸，"
            f"禁止用 `IF x > lim` 这类对 NaN 判假即放行的写法；② 所有除法必须在分母侧先判零，"
            f"不得先除后判；③ 状态机必须 ENUM + CASE 且带 ELSE 兜底，复位要先清锁存再判条件；"
            f"④ 不同工步的定时器必须各自独立，不得共用一个 TON 实例；"
            f"⑤ 同一输出变量只允许单点赋值，兜底分支也要把输出清到安全侧；"
            f"⑥ 每个变量同行中英双语注释并标注单位，公式两侧量纲必须自证一致；"
            f"⑦ 纯 IEC 61131-3 跨平台语法，禁 GVL、禁物理地址、禁 PROPERTY、禁构造函数式类型转换。"
            f"输出要求可直接编译通过，异常工况一律回落到安全默认值并给出有效性标志。")

def arch(name, cat, fn, cx):
    base = (f"架构思路：先做输入域收敛——把全部 REAL 入参（尤其组态参数、上限、增益、系数）"
            f"集中成一张合法性判据，用 `NOT(x <= lim)` 或 `x <> x` 捕获非有限值，"
            f"避免 NaN 在比较运算中恒假造成的 fail-open；判据结果落成单一的 _bCfgOk 位，"
            f"全块只依赖这一位，不重复散判。")
    if cx >= 3:
        unit = (f"功能实现用 ENUM + CASE 状态机，每相只做一件事：相内仅计算本相所需的中间量，"
                f"相迁移条件写在本相末尾，CASE 末尾一定带 ELSE 兜底迁故障相。"
                f"故障采用「请求位 + 锁存位」两段式：各相只置请求位，由段末唯一锁存点统一锁存并同步迁相，"
                f"避免多处写状态造成竞态。每相的超时用独立 TON 实例，TON 在块首无条件周期刷新。")
        safe = (f"防错设计：① 相位运算（角度/卷径比/传动比）先做 ±180° 或量程归一化，再做差，"
                f"防止跨界跳变；② 斜坡推进的步长先过非有限闸再累加，步长非法即归零保持原位；"
                f"③ 出口段统一做一次非有限复检，宁可输出零也不外泄 NaN；④ 使能丢失或故障锁存期，"
                f"所有执行给定立即归零到安全侧。")
        oop = ("OOP 解耦：把「度量」与「决策」分离——度量层只产出具名中间量（比值、偏差、速率），"
               "决策层只读这些量做相迁移，出口层只做单点赋值。三层之间不共享可写状态，"
               "因此单元测试可对度量层单独注入向量，不需要跑完整状态机。")
    else:
        unit = ("计算件不做状态机，按「预置默认 → 早退非法 → 主体计算 → 出口复检」四段式组织，"
                "任一前置校验失败即写哨兵值 -1 并 RETURN，调用方可据此区分「非法输入」与「结果确为 0」。")
        safe = ("防错设计：分母先判零再除；结果做物理域钳位（百分比 0~100、非负量不小于 0）；"
                "负结果不静默钳成 0，而是判物料/能量衡算矛盾并回哨兵，避免把错误掩盖成正常。")
        oop = ("OOP 解耦：纯函数式，无内部状态，所有输入显式列在接口上，"
               "便于在同一扫描周期内对多工位并行调用，也便于做参数扫描标定。")
    return base + unit + safe + oop

n = 0
with open(APP, 'a', encoding='utf-8', newline='\n') as f:
    for name, cat, cx, fn in added:
        src = open(disk[name], encoding='utf-8').read()
        rec = {"instruction": instr(name, cat, fn),
               "architecture_thought": arch(name, cat, fn, cx),
               "output": src,
               "meta": {"name": name, "category": cat, "complexity": cx, "round": "R89",
                        "license": "MIT", "origin": "clean-room"}}
        f.write(json.dumps(rec, ensure_ascii=False) + '\n')
        n += 1
print('appended', n, 'before', n_before, 'after', n_before + n)
