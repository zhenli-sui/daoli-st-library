# -*- coding: utf-8 -*-
"""R88 队列追加：从本地 codeload 抽取结果生成候选，三道去重后 append。"""
import json, re, hashlib, datetime

Q = r"C:\Library\_Staging_Raw\2026-11-25\candidate_queue.jsonl"
FP = r"C:\Library\_Staging_Raw\_dedup_fingerprints.json"
BLK = r"C:\Library\_Staging_Raw\2026-11-25\_r88_blocks.json"
OUT = r"C:\Library\_Staging_Raw\2026-11-25\_r88_add.json"

blocks = {(b["repo"], b["name"]): b for b in json.load(open(BLK, encoding="utf-8"))}

SHA = {
    "eponce00_TcForge": "713d028787784cd00fb1be3248966664bb38c5c6",
    "pcdshub_lcls-twincat-general": "071073654b7b9118ea7882df0070901093ffb7d0",
    "Beckhoff-USA-Community_SPT_V4_Samples": "470ce0f0acc28ac16e5237a60fb8259e9c456722",
}
REPO = {
    "eponce00_TcForge": ("eponce00/TcForge", "main"),
    "pcdshub_lcls-twincat-general": ("pcdshub/lcls-twincat-general", "master"),
    "Beckhoff-USA-Community_SPT_V4_Samples": ("Beckhoff-USA-Community/SPT_V4_Samples", "main"),
}
LIC = {
    "eponce00_TcForge": ("MIT", "green"),
    "pcdshub_lcls-twincat-general": ("BSD-3-Clause", "green"),
    "Beckhoff-USA-Community_SPT_V4_Samples": ("0BSD", "green"),
}

PICK = [
 ("eponce00_TcForge", "FB_AnalogInput", "DL_Device",
  "UNION 原始字到类型选择、质量门、量程钳位、工程单位换算、一阶 LPF 的一体化模拟量调理链（质量门先于换算，钳位先于滤波）",
  ["cfg.inputType 分支缺 ELSE 兜底会得错标度", "raw 到工程单位换算含裸除法，需除子闸", "OPC.UA 属性注解需剥离后再移植"]),
 ("eponce00_TcForge", "FB_IOQualityMonitor", "DL_Device",
  "四源（通信/设备/样本有效/样本序号）合成 IO 质量码，超时降级，原因枚举起因归类；序号不前进即判样本陈旧",
  ["首扫即计时，超时判定缺初始化闸会误报", "无样本与超时共用等待原因，根因分辨会丢", "超时入参 TIME 未做零值守卫"]),
 ("eponce00_TcForge", "FB_AlarmRateOfChange", "DL_Algo",
  "斜率越限报警：变化率按任务周期归一为 EU/s，首扫抑制防误跳，PV 有效性门内才推进历史",
  ["dt 取自 F_GetTaskCycleTime，移植须换固定周期入参", "斜率阈值为 0 时裸除法无闸", "首扫抑制依赖 bInit 单点，任务重启重入需复核"]),
 ("eponce00_TcForge", "FB_SwitchingPvPid", "DL_Algo",
  "双通道独立整定的 PID 择一驱动同一 CV，源切换时跟踪上一拍有效 CV 实现无扰迁移",
  ["无扰跟踪仅保一拍，切换瞬间微分冲击需人工闸", "两通道历史每拍清空，切回时积分重建易过冲", "源权威属应用层，本块不校验 source 与 quality 一致性"]),
 ("eponce00_TcForge", "FB_TwoPosActuator", "DL_Device",
  "双位执行器（推进/退回）状态机：双侧许可校验、配置变更检测、中止挂起、反馈不一致与行程超时故障",
  ["配置逐拍比对，配置抖动会反复触发 inhibit", "中止挂起无超时闸，永久 abort 即卡死", "进/退反馈同时为真时无显式冲突态"]),
 ("eponce00_TcForge", "FB_OperatorMailbox", "DL_Base",
  "单挂起命令加 8 条有界结果记录的操作员邮箱，TestAndSet 保护，按任务拥有者识别所有权冲突，请求 ID 要求跨重启唯一",
  ["无持久化，非 exactly-once，断电重放需上层幂等", "记录槽满无显式溢出计数，可能静默丢结果", "所有权冲突仅置标志不自复位，需外部清除"]),
 ("eponce00_TcForge", "F_ValidateRequester", "DL_Base",
  "RPC 命令门禁：源锁定期拒 OPERATOR 调用，故障期全拒；复位与确认类方法不得复用此函数",
  ["单一返回枚举，无法区分锁定与故障两种拒因", "无请求者优先级仲裁，仅二值判定"]),
 ("pcdshub_lcls-twincat-general", "F_ConvertTicksToUnixTimestamp", "DL_Base",
  "Windows 100ns 计时 ticks 转 Unix 秒，含 1601 到 1970 的 11644473600 秒 epoch 偏移",
  ["ULINT 直转 LREAL 超过 2^53 后丢精度，秒级会抖", "无负值与零值守卫，epoch 前时间得负秒", "常量硬编码未参数化"]),
 ("pcdshub_lcls-twincat-general", "FB_UnixTimeStamp", "DL_Base",
  "PLC 本地系统时间经时区换算输出 Unix 秒/毫秒/浮点秒四形态，bValid 门控输出可用性",
  ["依赖 FB_LocalSystemTime 与 FB_GetTimeZoneInformation，移植须整体替换", "注释自陈算法取自 StackOverflow，须 clean-room 重写", "bValid 为假时输出归 0 而非保持，消费侧易误读为 1970"]),
 ("pcdshub_lcls-twincat-general", "FB_ECATAutoRestart", "DL_Base",
  "EtherCAT 从站状态自愈：读状态、置态、失败计数，累计 5 次后停试并置错误码",
  ["错误计数只增不清，恢复后不自动归零", "置态与读态间无退避延时，密集重试会加剧总线抖动", "实现体为空仅声明骨，需 clean-room 补齐"]),
 ("Beckhoff-USA-Community_SPT_V4_Samples", "FB_HomeRoutine_CalibrationCam", "DL_Motion",
  "基于标定凸轮的 MC_Home 回零相序骨：标定位、凸轮捕获、位置锁定、完成；实现体分散在 Property/Method",
  ["实现体为空仅声明与相序变量，需 clean-room 补齐", "依赖 MC_Home 与 I_BasicAxis，属运动方言", "相序缺终止与超程兜底分支"]),
 ("pcdshub_lcls-twincat-general", "E_ECAT_STATES", "DL_Base",
  "EtherCAT 设备状态枚举 INIT/PREOP/SAFEOP/OP，strict 加 qualified_only 加 to_string 映射至平台常量",
  ["枚举值绑定 EC_DEVICE_STATE_* 平台常量，非 IEC 标准编号", "无非法态兜底分支", "纯类型定义无行为，单独使用增量有限"]),
]

q = [json.loads(l) for l in open(Q, encoding="utf-8") if l.strip()]
oldfp = json.load(open(FP, encoding="utf-8"))
have = {r.get("fp") for r in q}
now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")

add, skipped = [], []
for repo, name, cat, point, gaps in PICK:
    b = blocks.get((repo, name))
    if not b:
        skipped.append((name, "block-missing")); continue
    lic, tier = LIC[repo]
    full, br = REPO[repo]
    ins = b["inputs"]
    base = re.sub(r"^(fb_|fc_|i_|st_|e_|tc_|mc_|smc_|dl_)", "", name.lower())
    key = base + "|" + (",".join(sorted(i.split(":")[-1] for i in ins)) if ins else name.lower())
    h = hashlib.sha1(key.encode()).hexdigest()[:16]
    if h in have or h in oldfp:
        skipped.append((name, "fp-dup:" + h)); continue
    st = b["st"] + b["decl"]
    auto = []
    if re.search(r"%[IQM]", st): auto.append("含 %I/%Q 直接寻址，移植须抽象")
    if re.search(r"__SYSTEM|SysFile|FB_Ec|EC_DEVICE_STATE|T_AmsNetId|MC_Home|I_BasicAxis", st):
        auto.append("含平台方言依赖，clean-room 须剥离")
    if re.search(r"\bWHILE\b", st): auto.append("存在 WHILE，需守卫计数")
    if re.search(r"(?i)\bCASE\b", st) and not re.search(r"\bELSE\b", st):
        auto.append("CASE 无 ELSE 兜底")
    if name.startswith("E_"):
        newname = "E_DL_" + re.sub(r"^E_", "", name)
        kind = "TYPE"
    elif name.startswith("F_") and not name.startswith("FB_"):
        newname = "FC_DL_" + re.sub(r"^F_", "", name); kind = "FC"
    else:
        newname = "FB_DL_" + re.sub(r"^FB_", "", name); kind = "FB"
    path = b["file"].split("/", 1)[1] if "/" in b["file"] else b["file"]
    dial = ["TwinCAT3"]
    if "OPC.UA.DA" in st: dial.append("OPC_UA_DA")
    if "FB_LocalSystemTime" in st or "T_AmsNetId" in st: dial.append("Tc2_System")
    if "MC_Home" in st: dial.append("MC2_Motion")
    cand = {
        "name": newname, "suggest_category": cat, "kind": kind,
        "tier": tier, "license": lic,
        "source_url": "https://github.com/%s/blob/%s/%s" % (full, SHA[repo], path),
        "commit": SHA[repo], "extraction_point": point,
        "signature": ", ".join(ins[:10]), "loc": b["loc"],
        "dialect": dial, "defense_gaps": (gaps + auto)[:6],
        "dedup": {"name": "pass", "fingerprint": "new", "semantic": "new"},
        "priority": 1,
        "note": "绿区可改写；保留原版权声明写入 NOTICE；provenance mode=rewrite；源块名 %s" % name,
        "fp": h, "harvested_at": now, "code_excerpt": None,
    }
    add.append(cand); have.add(h)

print("to add:", len(add), "| skipped:", skipped)
for a in add:
    print("  + %-34s %-6s %-6s loc=%-4d" % (a["name"], a["tier"], a["license"], a["loc"]))
json.dump(add, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
