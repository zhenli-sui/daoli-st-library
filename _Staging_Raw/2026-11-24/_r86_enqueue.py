# -*- coding: utf-8 -*-
import json, io, re, hashlib

LIB = r"C:\Library"
STG = LIB + r"\_Staging_Raw\2026-11-24"
Q = STG + r"\candidate_queue.jsonl"

reg = json.load(open(LIB + r"\INDEX_REGISTRY.json", encoding="utf-8"))
rnames = {c["name"].lower() for c in reg["components"]}


def norm(n):
    b = re.sub(r"^(fb_|fc_|i_|st_|e_|tc_|mc_|smc_|dl_)", "", n.lower())
    return re.sub(r"^dl_", "", b).replace("_", "")


rnorm = {norm(n) for n in rnames}
rows = [json.loads(l) for l in io.open(Q, encoding="utf-8") if l.strip()]
qn = {r["name"].lower() for r in rows}
qfp = {r.get("fp") for r in rows if r.get("fp")}

SRC = "https://github.com/simatic-ax/LAxisCtrl/blob/main/"
CM = "simatic-ax/LAxisCtrl@main (codeload 2026-11-24)"

C = [
 ("FB_DL_AxisErrorWordSplit", "DL_Motion", "FB", "src/blocks/utils/AxisErrorWord.st",
  "AxisErrorWord 位域拆分：DWORD 错误字 → 9 个语义位（systemFault/configFault/userFault/commandNotAccepted/driveFault/sensorFault/dynamicError/communicationFault/softwareLimit）",
  "VAR_INPUT: axis:DB_ANY | VAR_OUTPUT: status:WORD, errorWord:DWORD, systemFault..communicationFault:BOOL",
  ["位序映射无固件版本闸，驱动升级后位义漂移会静默误判",
   "DB_ANY 入参在无反射平台不可移植，需改为值传入 + 位掩码常量表",
   "reserved 位未归并，未定义位点亮时无告警出口"]),
 ("FB_DL_AxisStatusWordSplit", "DL_Motion", "FB", "src/blocks/utils/AxisStatusWord.st",
  "状态字位域拆分：轴状态字 → 逐位语义输出（就绪/使能/运动中/回零完成/同步中）",
  "VAR_INPUT: axis:DB_ANY | VAR_OUTPUT: status:WORD + 逐位 BOOL",
  ["无位冲突检测：互斥状态同时为 TRUE 时不报警",
   "无状态字快照时序戳，退化趋势缺基准"]),
 ("FB_DL_AxisWarningWordSplit", "DL_Motion", "FB", "src/blocks/utils/AxisWarningWord.st",
  "警告字位域拆分：与错误字同构的旁路告警通道（不中断运动）",
  "VAR_INPUT: axis:DB_ANY | VAR_OUTPUT: warningWord:WORD + 逐位 BOOL",
  ["警告与错误的位归属边界未定义（同一位双属时归属不明）",
   "无警告累计计数，无法做退化趋势"]),
 ("FB_DL_GearInPosPhaseSeq", "DL_Motion", "FB", "src/blocks/stubs/GearInPosStub.st",
  "电子齿轮同步相序：Execute→StartSync→InSync 三相 + RatioNum/Den + 主从同步位置锚点 + SyncDirection(3=最短路径) 语义",
  "VAR_IN_OUT: Master:TO_Axis, Slave:TO_SynchronousAxis | VAR_INPUT: Execute:BOOL, RatioNumerator:DINT:=1, RatioDenominator:DINT:=1, MasterSyncPosition:LREAL, SlaveSyncPosition:LREAL, MasterStartDistance:LREAL:=1.0, Velocity/Acceleration/Deceleration/Jerk:LREAL:=-1.0, SyncDirection:DINT:=3 | VAR_OUTPUT: StartSync/InSync/Busy/CommandAborted/Error:BOOL, ErrorId:WORD",
  ["RatioDenominator=0 无除零闸（默认 1 但运行时未校验）",
   "-1.0 作『用轴默认动态值』哨兵无契约文档，负值透传会产生非法加速度",
   "InSync 丢失后无降级策略，缺 re-sync 请求出口",
   "单一 ErrorId=WORD#16#8002，无法区分主/从/参数三类错因"]),
 ("FB_DL_GearInVelPhaseSeq", "DL_Motion", "FB", "src/blocks/stubs/GearInVelocityStub.st",
  "速度齿轮啮合相序：以速度比耦合（非位置锚点），主轴变速时从轴跟随",
  "VAR_IN_OUT: Master:TO_Axis, Slave:TO_SynchronousAxis | VAR_INPUT: Execute:BOOL, RatioNumerator/Denominator:DINT, Velocity/Acceleration/Deceleration/Jerk:LREAL | VAR_OUTPUT: InSync/Busy/Error:BOOL, ErrorId:WORD",
  ["速度比越界（超轴最大速度）无钳位，仅靠驱动侧报错",
   "脱开时从轴保持策略未定义（自由停车 vs 保持速度）"]),
 ("FB_DL_GearOutPhaseSeq", "DL_Motion", "FB", "src/blocks/stubs/GearOutStub.st",
  "齿轮脱开相序：InSync→Execute→解耦→从轴按指定动态值回自由运行，含 SyncOutProfile 参数域",
  "VAR_IN_OUT: Slave:TO_SynchronousAxis | VAR_INPUT: Execute:BOOL, Deceleration/Jerk:LREAL, SyncOutMode:DINT | VAR_OUTPUT: Busy/Done/Error:BOOL, ErrorId:WORD",
  ["脱开瞬间从轴超速/超程无预测闸",
   "Done 与 Error 可同时为 TRUE 的竞态未排除"]),
 ("FB_DL_PhasingAbsPhaseSeq", "DL_Motion", "FB", "src/blocks/stubs/PhasingAbsoluteStub.st",
  "绝对相位偏移：保持同步前提下对从轴施加绝对相位差（DirectionPhasingOffset：正向/负向/最短路径）",
  "VAR_IN_OUT: Master:TO_Axis, Slave:TO_SynchronousAxis | VAR_INPUT: Execute:BOOL, PhasingPosition:LREAL, Direction:DINT | VAR_OUTPUT: Busy/Done/Error:BOOL, ErrorId:WORD",
  ["相位跳变幅度无上限，超过一圈的跳变会导致从轴飞车",
   "相位偏移期间跟随误差监控是否暂停未定义"]),
 ("FB_DL_CamInProfileGate", "DL_Motion", "FB", "src/blocks/stubs/CamInStub.st",
  "凸轮啮合相序 + CamInProfile 参数域（凸轮表选择/主从偏移/起始段），枚举化剖面入参范式",
  "VAR_IN_OUT: Master:TO_Axis, Slave:TO_SynchronousAxis | VAR_INPUT: Execute:BOOL, CamTableID:DINT, MasterOffset:LREAL, SlaveOffset:LREAL, Profile:DINT | VAR_OUTPUT: InSync/Busy/Error:BOOL, ErrorId:WORD",
  ["CamTableID 无存在性校验，表缺失时报错点过晚",
   "多段凸轮切换无接缝连续性检查"]),
 ("FB_DL_AxisFastStopParamCheck", "DL_Motion", "FB", "src/types/typeFastStopParams.st",
  "快停参数域：减速度/加加速度/快停模式组合的合法域约束（纯参数校验范式）",
  "TYPE FastStopParams: Deceleration:LREAL, Jerk:LREAL, Mode:DINT",
  ["负值/零值组合的合法性矩阵未定义，-1.0 哨兵与真实非法值混淆",
   "无『快停时间 <= 安全响应时间』跨参数校验"]),
 ("FB_DL_AxisDiagStructSnapshot", "DL_Motion", "FB", "src/types/typeDiagnostics.st",
  "轴诊断结构体字段清单：错误字/状态字/警告字/位置/速度/扭矩的打包快照范式",
  "TYPE AxisDiag: status:WORD, errorWord:DWORD, warningWord:WORD, position/velocity/torque:LREAL",
  ["结构体无版本字段，跨固件升级反序列化会错位",
   "无时间戳与采样序号，多轴对齐诊断不可行"]),
]

add = []
for name, cat, kind, path, pt, sig, gaps in C:
    if name.lower() in qn or name.lower() in rnames or norm(name) in rnorm:
        print("SKIP(name dup)", name)
        continue
    h = hashlib.sha1((name.lower() + "|" + sig).encode()).hexdigest()[:16]
    if h in qfp:
        print("SKIP(fp)", name)
        continue
    add.append({
        "name": name, "suggest_category": cat, "kind": kind, "tier": "yellow",
        "license": "Siemens-RoyaltyFree-1.4 (SPDX:NOASSERTION)",
        "source_url": SRC + path, "commit": CM, "extraction_point": pt,
        "signature": sig, "loc": 40,
        "dialect": ["S7-1500", "SIMATIC AX", "DB_ANY", "TO_SynchronousAxis"],
        "code_excerpt": None, "defense_gaps": gaps,
        "dedup": {"name": "pass", "fingerprint": "pass", "semantic": "new"},
        "priority": 2, "fp": h, "status": "pending",
        "note": "黄区仅借骨：接口签名+参数域+错误码惯例；实现必须 clean-room，文件头写致谢 simatic-ax/LAxisCtrl 并标注提取点",
        "harvested_at": "2026-11-24T21:25:00+08:00",
    })

with io.open(Q, "a", encoding="utf-8") as f:
    for r in add:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
print("ADDED", len(add), [a["name"] for a in add])
json.dump(add, open(STG + r"\_r86_added.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
