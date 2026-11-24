#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""closeout_r60.py —— R60 主控直跑收口（R335）：机检 13 件（12 新 + 1 返修）
+ 注册 12 新件 + TwoStepConfirm 升版 + JSONL 增量（12 新增 + 1 重注入 R248）
+ ROADMAP 勾选断言（R247 锚定正则 + 数量断言，R269 常驻）。"""
import io, os, json, re, sys
from compile_gate_v0 import gate_file, strip_comments

ROOT = r"C:\Library"
REG = os.path.join(ROOT, "INDEX_REGISTRY.json")
JSONL = os.path.join(ROOT, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl")
ROAD = os.path.join(ROOT, "ROADMAP.md")
NOW = "2026-11-21T10:20:00+08:00"
VER = "2.52.0"

# name, cat, type, complexity, batch, tags, instruction, arch
NEW = [
 ("FC_DL_SearchMinMaxDint", "DL_MathData", "FC", 2, 1,
  ["t2-1-lgf-math", "min-max", "array-scan", "dint", "clean-room"],
  "料仓秤重缓冲与批次计量需在 DINT 域（毫克/计数单位）数组上单遍求最小最大并同出索引：前 nCount 个元素有效，要求一次循环同时给出最小值/最大值与首命中索引，避免两次遍历；无效样本按组态开关跳过并计数，全量无效时不得返回 0 号位伪极值；nCount 越界钳位并置信息级码；输出极值/双索引/有效标志/跳过计数。",
  "单遍扫描架构：入口做 nCount 钳位 [1,4096] 与有效标志预置；FOR 单循环内 cmp 有效样本后双分支更新 nMin/nMax 与首命中索引（uMinIdx 仅在严格小于时更新，保证首命中口径）；无效哨兵 DL_SMM_INVALID 按 bIgnoreInvalid 门控跳过并累加 nSkipped；全无效置 bValid=FALSE 且极值出口归零不落 0 号位；与 LREAL 属主件 FC_DL_SearchMinMax 头注释互引分工（浮点有限性判据归后者），纯函数无状态可重入。"),
 ("FC_DL_SearchMinMaxUdint", "DL_MathData", "FC", 2, 1,
  ["t2-1-lgf-math", "min-max", "array-scan", "udint", "clean-room"],
  "累计流量/脉冲计数等 UDINT 无符号域的极值检索需与 DINT 域件同族对称：前 nCount 个元素有效，单遍同出最小最大与首命中索引；无效哨兵取 16#FFFF_FFFF（无符号域上界），按开关跳过并计数；全量无效不返回伪极值；nCount 越界钳位置码；输出极值/双索引/有效标志/跳过计数。",
  "与 DINT 件同构架构（同规格向量表、码位段连号）：单遍 FOR 扫描 + 严格小于/大于双分支更新首命中索引；无符号域无 NaN，无效性只由哨兵常量 DL_SMM_INVALID_U 表达，闸为 uVal <> DL_SMM_INVALID_U；哨兵取上界而非 0，防 0 值合法样本被误跳；全无效置 bValid=FALSE；与 DINT 属主件头注释互引「域重载对」关系，禁在两件中各造一份不同哨兵口径。"),
 ("FB_DL_RolloverCounterUdint", "DL_Base", "FB", 3, 1,
  ["t2-1-lgf-counter", "counter", "rollover", "udint", "overflow-safe"],
  "累计表/流量计 UDINT 计数会在 16#FFFF_FFFF 处回绕，直接做差得到负增量：需按模运算求真实增量并累加到 64 位宽域累计值，回绕拍单独出单拍脉冲并计数；累计值上界到顶后饱和保持不再回绕；输入采样周期内多次回绕（周期过长）无法分辨时置可疑标志；预置沿可装载初值；输出增量/宽域累计/回绕脉冲/回绕计数/可疑标志。",
  "模差回绕架构：段 0 无条件刷新采样沿与预置沿（R7）；增量 = (uNow - uPv) 在 UDINT 模意义下取差（无符号减法天然回绕正确），判定回绕条件 uNow < uPv 时置单拍脉冲并累加 nRollCnt、同时给 nAmbCnt 可疑计数（若单周期内增量超半域）；宽域累计用 LINT 累加并对上界饱和；预置沿装载 uPreset 并同步 uPv 基准；出口含增量/累计/脉冲/计数/可疑，四者同行中英双语注释。"),
 ("FB_DL_ReqAckHandshake", "DL_Base", "FB", 3, 1,
  ["self-std", "handshake", "request-ack", "retry", "timeout"],
  "上位/机器人/视觉等外部单元交互普遍是请求-应答：请求上升沿进入应答等待，应答窗内收到应答输出确认单拍；窗到期未应答则输出重试单拍并进入重试间隔，重试达上限仍不应答锁存故障；重试间隔必须短于应答窗（否则重试语义退化为一次性），配置越界时在组态闸锁存故障而不是只写注释；应答在重试间隔内迟到不得被吞；输出确认/重试/故障码/重试计数/等待中标志。",
  "三段相位机架构：E_RA_IDLE→E_RA_WAIT→E_RA_GAP 三态，CASE 含 ELSE 落 IDLE；段 0 无条件刷新两枚 TON（tAck 窗 / tRetry 间隔）与请求沿（R7，实例禁置分支内）；段 2 组态闸校验 tAck > tRetry > 0，违反即锁存 eCfgBad 并不进入等待相（R239 双窗配比可观测化）；等待相内 bAck 电平命中即出单拍 bDone 并回 IDLE；间隔相到期若重试未达上限则回 WAIT 并出 bRetry，达上限锁存 eNoAck；失能时清相位与计数但保留锁存（失能分支加相判据防改写成功拍）；出口确认/重试/故障/计数/等待中。"),
 ("FC_DL_BitFieldExtractLword", "DL_Base", "FC", 2, 2,
  ["t2-1-lgf-bitlogic", "bit-field", "lword", "extract", "mask"],
  "设备诊断字/状态字常为 64 位打包位域，需按起始位宽提取为 UDINT 并支持符号扩展与饱和：起始位 + 位宽越界钳位（起始 0..63，位宽 1..64），跨高位时用掩码右移而非大位移（部分平台移位超 32 位行为不一致）；超宽请求置越域码并输出零；可选零扩展/符号扩展两模式；纯函数，输出提取值为 UDINT 与有效/越域标志。",
  "掩码桥接架构：位宽=64 时整字直出（避免移位 64 的未定义行为）；否则先右移起始位得高半区，再与 ((1<<宽)-1) 掩码；高位区间（起始 ≥32）走 LWORD 高半区取法（LW / 16#0000_0001_0000_0000 取高 32 位）再窄化为 UDINT，禁依赖平台对 64 位移位的扩展行为；符号扩展模式在最高位为 1 时按位宽补高位；越域先置码后返回零，纯函数无状态。"),
 ("FC_DL_Affine2DChain", "DL_MathData", "FC", 3, 2,
  ["t2-1-lgf-math", "affine", "transform-chain", "2d", "homogeneous"],
  "视觉标定与工位坐标系换算需把多次二维仿射变换（平移+旋转+缩放）串联成一次复合变换再作用于点：变换序列长度 ≤8，按顺序复合，复合结果矩阵作用于输入点；序列长度 0 视为恒等变换；nCount=1 时也必须走完整复合路径（含行列式校验），不得跳过委托；复合矩阵行列式近零（奇异）时置奇异标志并令 bValid=FALSE，不得外泄坐标；输出复合后坐标/复合矩阵/行列式/奇异与有效标志。",
  "链式复合架构：变换以 ARRAY[0..7,0..2,0..2] 三维数组传参（不新造 TYPE，R264 无引用债），逐级委托 FC_DL_Affine2DCompose（R140 复用纪律）；复合即 3×3 齐次矩阵连乘，第 0 级初始化恒等矩阵，然后 FOR k:=0..nCount-1 逐级左乘（**不设 nCount=1 的短路分支**——短路会绕过属主的行列式判据，R59/R60 终审实证）；复合完成后由属主判 det 与容差：|det| < eps 置 bSing 与 bValid=FALSE 并零化出口；矩阵元素全部同行中英双语注释并标明行/列语义。"),
 ("FC_DL_ThdCalc", "DL_MathData", "FC", 2, 2,
  ["self-std", "thd", "power-quality", "harmonic", "aggregate"],
  "变频器与整流负载供电侧需算总谐波失真率 THD 供能效与治理判据：输入为幅值序列（0 号位基波，1..N-1 为各次谐波），输出 THD = √(Σh²)/|h1|；基波近零或非有限必须拒绝相除并置故障级码；谐波幅值按绝对值域参与（负幅值视为相位翻转的幅值等价）；元素数少于 2 无谐波可算置信息级码；输出 THD 百分比/有效标志/错误码。",
  "聚合比值架构：入口做基波与各谐波的双重非有限判据（x<>x 判 NaN 与 (x-x)<>(x-x) 判 Inf，R258 三件套同拍置 eErr+bError+bValid）；基波 |h1| < 1E-9 前置拦截不进除法（R4）；FOR 1..nCount-1 累加 |h|² 后开方再除基波，单点归一不做多段回夹（R5）；nCount 钳位 [2, 容量]；出口 THD/有效/码，与 FC_DL_HarmonicSpectrumBin（分箱属主）、FC_DL_FftRadix2（变换属主）头注释互引分工，本件不分箱不变换。"),
 ("FB_DL_InputShaperZv", "DL_Algo", "FB", 3, 2,
  ["self-std", "input-shaping", "zv", "vibration-suppress", "control"],
  "桁架/机械手定位后残余振动拖慢节拍：对速度指令做 ZV 双脉冲整形，按阻尼比 ζ 与固有频率 ωn 合成两脉冲（幅值 1/(1+A) 与 A/(1+A)，间隔 Δt）抑制阶跃激起的残余振动；ζ 与 ωn 越界（ζ 需 0..0.99，ωn > 0）钳位并置组态码；Δt 过小（低于 2 个扫描周期）退化为直通并置降级标志；急停/旁路时直通；输出整形后指令/Δt 估算/直通与降级标志。",
  "前馈整形架构：段 0 无条件刷新次脉冲 TON 与触发沿（R7）；触发沿当拍出首脉冲、TON 到期拍出次脉冲，两脉冲均单拍且统一出口段每拍先预置 FALSE（R256）；A = exp(-ζπ/√(1-ζ²)) 用 EXPT 求解，ζ 用 ABS 容差判定而非 <> 比较（R281 本轮立规）；Δt 内部一律秒计算，转 TIME 时统一乘 1000 经 LREAL_TO_TIME 落毫秒（R342 时间口径单一化，禁跨日历类型链）；降级直通由 Δt < 2 扫描周期或旁路位判决，枚举 E_ZV_MODE_* + CASE 含 ELSE 落直通；与 FB_DL_NotchFilter（反馈侧频域抑制属主）头注释互引分工。"),
 ("FC_DL_InterpolateTable3D", "DL_MathData", "FC", 4, 3,
  ["t2-1-lgf-math", "interpolation", "3d-table", "trilinear", "lookup"],
  "发动机 MAP、热处理炉温曲线等二维/三维查表需在轴向量非等距的三维表上做三线性插值：三轴轴向量必须严格单调，非单调置组态码并不出值；输入点超表范围按边界钳位（不外插）并置越域标志；轴向量元素非有限逐点判据；表维度 ≤16×16×16，越界下标每次取值前钳位；输出插值结果/越域标志/有效标志。",
  "三线性插值架构：入口做标量入参非有限闸（R272 显式枚举）+ 三轴单调性校验（逐轴 FOR 比较相邻元素，非单调即置码早退）；轴定位用二分/线性定位得小区间索引与归一化权重，索引统一钳位 [0, n-2]（下界）与 [0, n-1]（上界）防越界读；八个角点按 trilerp 加权求和，权重和恒为 1 由构造保证；越界不插值（外插在本件禁止）只钳位并置标志；数组全部显式上界，禁动态索引；纯函数无状态。"),
 ("FB_DL_ValveTerminalDiag", "DL_Device", "FB", 3, 3,
  ["t2-6-rockwell-aoi", "t2-2-lbp", "valve-terminal", "diagnostics", "solenoid"],
  "阀岛（多位电磁阀端子）需按命令与反馈做在位诊断：每路比较命令位与反馈位，反馈异常持续去抖窗后判该路故障并隔离，隔离后不拖垮其余路；线圈短路/开路按反馈双沿特征区分（有命令无反馈=开路，无命令有反馈=短路），持续错位无法归因时置未定型；全部路故障时置组级故障；输出各路状态字/故障路数/故障码/去抖中标志。",
  "见性诊断架构：段 0 无条件刷新逐路去抖 TON（定长数组实例，R7）+ 命令/反馈沿；每路差异位先入去抖，去抖到期才置故障锁存位（防抖）；故障分类用「命令位 × 反馈位」二值组合查表（枚举 E_VLV_DIAG_* + CASE 含 ELSE 落未定型）；隔离由故障位与命令字按位与非运行期移位；组级故障由故障路数达阈值判决；复位沿清全部锁存与去抖；出口状态字/路数/码/去抖中，禁把「组态标记」写进诊断路径（本轮自纠点：删 `_nBad:=_nBad` 自赋值，改独立组态位）。"),
 ("FB_DL_AxisCmdArbiter", "DL_Motion", "FB", 3, 3,
  ["t1-6-plcopen", "motion", "command-arbiter", "priority", "source-identity"],
  "单轴驱动同时受安全、手动、自动、上位四路命令源驱动，必须严格优先级并保留胜出源身份：每拍全量重判，输出胜出源标签与整份命令字（含源身份，防赢了仲裁丢身份）；源标签与结构体内容不符时视为该源未请求；切换拍出单拍脉冲；输入非有限时降级到安全源，且降级标志与胜出源标签必须同步（不得一个报安全源、另一个报旧源）；输出命令字/胜出源/切换脉冲/降级标志。",
  "纯组合件架构（R227 显式声明无相位机）：每拍按 安全>手动>自动>上位 全量重判，IF/ELSIF 链顺序即优先级，无陈旧保持；源请求判据 = 使能位 AND 结构体内源标签一致（防错配）；非有限输入触发降级分支：**同时**改写 eWinner、命令字内容与 bDegraded 三处，保持双通道一致（R282 本轮立规：降级不得只改标签或只改内容）；切换脉冲由本拍胜出源 <> 上拍胜出源生成；E_DL_AxisCmdSrc 与 ST_DL_AxisCmd 属主为本文件（R264 全库唯一定义）。"),
 ("FB_DL_ShiftHandoverCheck", "DL_Process", "FB", 3, 3,
  ["self-std", "shift-handover", "snapshot", "checklist", "confirm"],
  "班次交接需在交接时点取运行快照（产量与报警计数）并逐条确认未决事项：交接开始沿锁存快照，交接窗内逐条确认，全部确认即出完成单拍；窗到期仍有未决项则升级故障码并转未完成态；交接窗为零或负判组态非法并不得进入交接相；到期拍恰有确认沿时按确认处理不得同拍报超窗；输出快照产量/快照报警数/未决项数/完成脉冲/故障码。",
  "快照-确认双段架构：E_SH_IDLE→E_SH_CHECK→E_SH_DONE 三态，CASE 含 ELSE 落 IDLE；段 0 无条件刷新交接窗 TON 与开始沿（R7）；进入条件 = 开始沿 AND 使能 AND 窗合法 AND 无锁存；退出条件族 = 全确认（完成）/ 窗到期（升级）/ 失能（退相）三条逐条对偶（R259）；交接开始沿锁存快照并置 _nPending（快照后不再跟随实时值，R243 快照与镜像分离）；交汇段先消化本拍确认沿再消化超窗迁移（R275）；出口未决项数由快照清单逐条与确认位比对得出，注释与实现口径须一致（本轮终审 D7 挂账点）。"),
]


def checks(path):
    """7 红线 + R271/R272/R261/R263/R262/R244/R240 增量机检。"""
    src = io.open(path, encoding="utf-8", errors="replace").read()
    code, issues = strip_comments(src)
    up = code.upper()
    # R244 禁止词（全篇含注释）
    for w in ("TODO", "占位", "待补", "同上", "类似", "TBD", "FIXME"):
        if w in src:
            issues.append("R244 禁止词命中：%s" % w)
    # R261 自赋值死语句
    for m in re.finditer(r"([A-Za-z_]\w*)\s*:=\s*\1\s*;", code):
        issues.append("R261 自赋值死语句：%s" % m.group(1))
    # R262 TRUNC 截断式转换
    if re.search(r"(?<![_A-Z0-9])TRUNC\s*\(", code):
        issues.append("R262 出现 TRUNC 截断式转换")
    # R263 枚举成员单冒号
    for m in re.finditer(r"^\s*([A-Za-z_]\w*)\s*:\s*[0-9]", code, re.M):
        issues.append("R263 枚举成员单冒号：%s" % m.group(1))
    # R240 声明区完整性（近似：体引用 - 声明集合）
    decl = set()
    for blk in re.findall(r"\bVAR[_A-Z]*\b(.*?)\bEND_VAR\b", code, re.S | re.I):
        for m in re.finditer(r"^\s*([A-Za-z_]\w*)\s*(?:,\s*[A-Za-z_]\w*\s*)*:", blk, re.M):
            decl.add(m.group(1).upper())
            for extra in re.findall(r",\s*([A-Za-z_]\w*)\s*:", m.group(0)):
                decl.add(extra.upper())
    KW = set("""IF THEN ELSE ELSIF END_IF CASE OF END_CASE FOR TO BY DO END_FOR WHILE END_WHILE
    REPEAT UNTIL END_REPEAT RETURN EXIT TRUE FALSE AND OR NOT XOR MOD ABS SQRT EXPT TON R_TRIG F_TRIG
    LREAL REAL DINT INT UDINT UINT BOOL WORD DWORD LWORD SINT USINT TIME DATE TOD DT STRING BYTE
    VAR VAR_INPUT VAR_OUTPUT VAR_IN_OUT VAR_TEMP VAR_STAT END_VAR TYPE END_TYPE STRUCT END_STRUCT""".split())
    body_ids = set(x.upper() for x in re.findall(r"\b([A-Za-z_]\w*)\b", code))
    unknown = sorted(i for i in body_ids - decl - KW
                     if i.startswith("_") or i.startswith("B") or i.startswith("F"))
    # 仅报告下划线开头（内部量）的悬空引用，避免类型/函数名误报
    dangling = [i for i in unknown if i.startswith("_")
                and not re.search(r"\b%s\b\s*(?::=|=>|:)" % i, code)]
    if dangling:
        issues.append("R240 疑似悬空引用（下划线内部量）：%s" % ",".join(dangling[:6]))
    # R272 浮点入参闸覆盖：按 R272 原文「命中即挂账」→ 计 WARN，不作 FAIL
    warns = []
    fin = re.findall(r"^\s*(f\w+)\s*:\s*(?:L?REAL)\s*;", code, re.M)
    gate = len(re.findall(r"_bFin|bFin", code)) + len(re.findall(r"(\w+)\s*<>\s*\1", code))
    if fin and gate == 0:
        warns.append("R272 浮点入参 %d 个，未见 _bFin 闸或非有限自比较判据（挂账核对）" % len(fin))
    # 双语注释抽样（声明行含 // 的比例，取 src 保留注释）
    decl_lines = [l for l in src.split("\n") if re.match(r"^\s*\w+\s*:\s*\w+", l)]
    bilingual = [l for l in decl_lines if "//" in l]
    return src, issues, warns, len(decl_lines), len(bilingual)


def main():
    d = json.load(io.open(REG, encoding="utf-8"))
    names = {c["name"] for c in d["components"]}
    fails = []
    report = []
    total_decl = total_bi = 0
    for it in NEW:
        p = os.path.join(ROOT, it[1], it[0] + ".st")
        if not os.path.exists(p):
            fails.append((it[0], ["文件缺失"]))
            continue
        src, g6, w6, nd, nb = checks(p)
        _, g = gate_file(p)
        iss = g6 + g
        total_decl += nd
        total_bi += nb
        if it[0] in names:
            iss.append("撞名：已在册")
        report.append((it[0], len(src.split("\n")), len(iss), iss, w6))
        if iss:
            fails.append((it[0], iss))
    # 返修件机检
    fix = os.path.join(ROOT, "DL_Base", "FB_DL_TwoStepConfirm.st")
    fsrc, fg6, fw6, fnd, fnb = checks(fix)
    _, fg = gate_file(fix)
    fiss = fg6 + fg
    report.append(("FB_DL_TwoStepConfirm(v1.0.1)", len(fsrc.split("\n")), len(fiss), fiss, fw6))
    if fiss:
        fails.append(("FB_DL_TwoStepConfirm", fiss))

    print("== 机检 %d 件 ==" % len(report))
    nwarn = 0
    for n, l, k, iss, w6 in report:
        nwarn += len(w6)
        print("  %-32s %4d 行  FAIL=%d WARN=%d %s%s" % (n, l, k, len(w6),
              "" if not k else iss[:3], "" if not w6 else " | " + w6[0][:40]))
    print("双语注释抽样：%d/%d = %.1f%%" % (total_bi, total_decl, 100.0 * total_bi / max(1, total_decl)))
    print("FAIL 件数 = %d ｜ WARN 项 = %d（挂账，不阻断）" % (len(fails), nwarn))
    if fails:
        print("!! 机检未全通过，中止收口（不出半成品账）")
        for n, i in fails:
            print("  ", n, i)
        return 1

    # ---- 注册 ----
    for it in NEW:
        p = os.path.join(ROOT, it[1], it[0] + ".st")
        d["components"].append({
            "name": it[0], "category": it[1], "type": it[2],
            "file_path": p,
            "function_tags": it[5] + [it[0].lower()],
            "complexity": it[3], "version": "1.0.0",
            "registered_at": NOW,
            "line_count": len(io.open(p, encoding="utf-8").read().split("\n")),
            "code_segment": "", "source": "r60-plan",
        })
    # 返修件升版
    bumped = 0
    for c in d["components"]:
        if c["name"] == "FB_DL_TwoStepConfirm":
            c["version"] = "1.0.1"
            c["registered_at"] = NOW
            c["line_count"] = len(fsrc.split("\n"))
            bumped += 1
    assert bumped == 1, "TwoStepConfirm 升版未命中"
    # counts / total 重算
    cnt = {}
    for c in d["components"]:
        cnt[c["category"]] = cnt.get(c["category"], 0) + 1
    d["counts"] = {k: cnt[k] for k in ("DL_Base", "DL_MathData", "DL_Algo",
                                       "DL_Device", "DL_Motion", "DL_Process")}
    d["total_components"] = len(d["components"])
    d["version"] = VER
    d["last_updated"] = NOW
    # 回读断言
    s = sum(d["counts"].values())
    assert s == d["total_components"], "counts 与 total 不一致 %d/%d" % (s, d["total_components"])
    io.open(REG, "w", encoding="utf-8").write(json.dumps(d, ensure_ascii=False, indent=1))
    print("\n== 注册 ==\ntotal=%d counts=%s version=%s" % (d["total_components"], d["counts"], d["version"]))

    # ---- JSONL ----
    lines = io.open(JSONL, encoding="utf-8").read().splitlines()
    bad = 0
    for l in lines:
        try:
            json.loads(l)
        except Exception:
            bad += 1
    # 重注入返修件（R248）
    fix_name = "FB_DL_TwoStepConfirm"
    reinj = 0
    for i, l in enumerate(lines):
        if fix_name in l and '"instruction"' in l:
            o = json.loads(l)
            o["instruction"] = o["instruction"].rstrip() + \
                "（v1.0.1 返修版：修 R275 同拍竞态——窗口到期拍恰有二按沿时按确认成立，见 REVIEW_R60.md 修法）"
            o["output"] = fsrc
            lines[i] = json.dumps(o, ensure_ascii=False)
            reinj += 1
            break
    added = 0
    for it in NEW:
        p = os.path.join(ROOT, it[1], it[0] + ".st")
        o = {"instruction": it[6], "architecture_thought": it[7],
             "output": io.open(p, encoding="utf-8").read()}
        lines.append(json.dumps(o, ensure_ascii=False))
        added += 1
    io.open(JSONL, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    # 新增行复验
    chk = io.open(JSONL, encoding="utf-8").read().splitlines()
    newbad = 0
    for l in chk[-added:]:
        try:
            json.loads(l)
        except Exception:
            newbad += 1
    print("== JSONL ==\n原 %d 行（历史 bad=%d）→ 新增 %d + 重注入 %d → 现 %d 行，新增行 bad=%d"
          % (len(chk) - added, bad, added, reinj, len(chk), newbad))
    assert newbad == 0 and reinj == 1, "JSONL 增量校验失败"

    # ---- ROADMAP 勾选断言（R247/R269）----
    rt = io.open(ROAD, encoding="utf-8").read()
    before = len(re.findall(r"^- \[ \]", rt, re.M))
    ticked = []
    for it in NEW:
        pat = r"^- \[ \] \*\*[^｜]*｜`%s`：" % re.escape(it[0])
        if re.search(pat, rt, re.M):
            rt = re.sub(pat, lambda m: m.group(0).replace("- [ ]", "- [x]", 1), rt, count=1, flags=re.M)
            ticked.append(it[0])
    after = len(re.findall(r"^- \[ \]", rt, re.M))
    if ticked:
        io.open(ROAD, "w", encoding="utf-8").write(rt)
    assert before - after == len(ticked), "ROADMAP 勾选数量断言失败"
    print("== ROADMAP ==\n待办 %d → %d（勾 %d 条：%s）" % (before, after, len(ticked), ticked or "无（12 名零在册）"))
    print("\nRESULT: PASS  件=%d  JSONL=%d  registry=%d" % (len(report), len(chk), d["total_components"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
