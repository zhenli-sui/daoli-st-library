# -*- coding: utf-8 -*-
"""R67 收口脚本：registry 注册（8 新 + 3 版本升级）+ JSONL 追加（8 新 + 3 返修重注入）+ 断言"""
import io, json, os, shutil, datetime

LIB = r"C:\Library"
REG = os.path.join(LIB, "INDEX_REGISTRY.json")
JSL = os.path.join(LIB, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl")
BAK = os.path.join(LIB, "_archive", "registry_backups", "INDEX_REGISTRY.json.bak_r67")

WRAP_DESC = "IEC 61131-3 标准语义（道莅防御性实现，委托平台内建）"

def st_read(cat, name):
    p = os.path.join(LIB, cat, name + ".st")
    src = io.open(p, encoding="utf-8").read()
    return p, src

# (name, cat, ty, cx, srcdesc, om, tag, tags, (instruction, architecture_thought))
NEW = [
 ("FC_DL_CalcDistance2D","DL_MathData","FC",4,"西门子 LGF Math 分类语义借鉴，clean-room 重写","classification","lgf-math",["distance","2d","hypot-scaling","overflow-guard","position","lgf-math","cleanroom","r67-new"],
  ("AGV 小车两目标点直线距离计算：给出两点平面坐标(可为大数值毫米坐标)，求欧氏距离用于行程估算、就近停靠点选择、路径段长度累计。边界：输入支持大坐标不溢出；m=0 退化分支除零闸；错误码 01 输入面/02 数值面分立报告。","缩放防溢出架构：d=m*sqrt((dx/m)^2+(dy/m)^2)，先取 |dx|/|dy| 大者为 m 归一，平方项恒 <=1 不溢出；m=0 时退化为直线判分支；纯函数无状态；与 FC_DL_AngleDiffRad（角差）正交互引（距离 vs 角度）。")),
 ("FC_DL_AngleDiffRad","DL_MathData","FC",3,"西门子 LGF Math 分类语义借鉴，clean-room 重写","classification","lgf-math",["angle","radian","wrap-around","signed-diff","encoder","lgf-math","cleanroom","r67-new"],
  ("编码器/旋转轴角度差计算：求两弧度角的最短带符号差，用于回转工位对位偏差、云台指向误差、两编码器同步偏差监视。边界：输入任意弧度值先整圈归约；输出域规范 [-pi, pi]；跨 ±pi 回绕正确（359 度到 1 度差为 2 度而非 358 度）；nTurn 走 LREAL 不进 DINT 溢出面。","TRUNC 整圈归约 + ±pi 单次平移两步法：先减整圈数把差压入一圈内，再按 ±pi 边界单次平移归约，避免循环取模的浮点累积误差；输出域复核头注声明；与 FC_DL_WrapAngleDeg（归约单值）分工互引。")),
 ("FC_DL_NormTo01","DL_MathData","FC",3,"西门子 LGF Math 分类语义借鉴，clean-room 重写","classification","lgf-math",["normalize","linear-map","clamp","zero-range","scaling","lgf-math","cleanroom","r67-new"],
  ("传感器原始值归一化：把原始读数按工程量程线性映射到 0..1（如电位器 0~10V、料位 0~5000mm），供 PID 归一化输入、百分比显示、跨通道融合加权。边界：反向域（xHi<=xLo）=码01 拒绝；零域宽容差判=码02；超界钳位到 0/1 附码03 信息级不置 bError；非有限输入走 02 面。","三码分立架构：配置面（反向域）与数据面（非有限）分立错误码，超界为信息级钳位仍可用（附码报告不故障）；宽容差判零域防浮点误判；纯函数无状态；与 FC_DL_ScaleLinear（任意域映射）互引分工（固定 0..1 vs 任意目标域）。")),
 ("FC_DL_SlewRateCalc","DL_MathData","FC",4,"西门子 LGF Technology 分类语义借鉴，clean-room 重写","classification","lgf-technology",["slew-rate","rate-of-change","delta","guard","diagnostic","lgf-technology","cleanroom","r67-new"],
  ("过程量变化率在线计算：相邻两次采样的差值除以时间间隔得单位/秒变化率，用于温度爬升速率监视、压力骤降报警、执行器卡滞诊断（应动不动）。边界：dt<=0（含首次调用 dt 无效）前置闸不出数；NaN 自反判防漏闸；差值与结果双非有限复核；无状态驻留由调用方持有上次值。","前置闸架构：dt 有效性（>0 且非有限拒绝）先行，差值非有限与结果非有限双复核三面把守；除零结构性不可达（dt>0 闸后）；纯函数设计由调用方管理采样节拍，与 FB_DL_RateLimiter（限速率执行器）互引（诊断测量 vs 执行限幅）。")),
 ("FC_DL_HexToStr","DL_MathData","FC",3,WRAP_DESC,"internal","iec-std-wrapper",["hex","string","byte-array","dump","diagnostic","iec-std-wrapper","internal","r67-new"],
  ("通讯报文十六进制转储：把接收缓冲字节串转成大写 HEX 文本（如 1A 2B 3C），用于报文日志留档、HMI 调试显示、通讯故障抓包比对。边界：输入超 127 字节按整字节截断并置标志不静默；输出定长预留防 STRING 溢出；委托平台字节/字符串内建，不重实现编码内核。","IEC 61131-3 标准语义的道莅防御性实现：SHR 半字节提取 + 查表映射（委托标准移位与字符串内核）；R49 四步法（判超限置码→钳长→写入→REPLACE 显式终结 $00）；SHR 移位量 4<8 合规声明；与 FC_DL_StrToHex 逆操作互引。")),
 ("FC_DL_StrToHex","DL_MathData","FC",4,WRAP_DESC,"internal","iec-std-wrapper",["hex","parse","string","byte-array","validation","iec-std-wrapper","internal","r67-new"],
  ("HEX 文本解析入缓冲区：把人工输入或上位机下发的 HEX 字符串（如『1A2B3C』）解析为字节串写入发送缓冲，用于参数下发通道、维修工单手输指令、协议兼容桥接。边界：非法字符=码01、奇数长度=码02、容量不足=码03 三面分立；失败零写入（原子性）；委托标准字符串内核 MID 查表判别。","IEC 61131-3 标准语义的道莅防御性实现：MID 查表判别（不用 STRING_TO_BYTE 对字母的十进制串歧义解析，编码期自纠）；先全量校验后写入的两阶段原子架构，失败零副作用；容量闸先行防越界；与 FC_DL_HexToStr 逆操作互引。")),
 ("FB_DL_LastGoodValueHold","DL_Base","FB",4,"IEC/NE43 失效保持语义借鉴 + 道莅原创架构","classification","ne43",["signal-loss","hold-last-value","stale","ne43","failover","ne43","cleanroom","r67-new"],
  ("传感器失效值保持：信号品质失效（NE43 故障位/超量程）时输出保持最后有效值，恢复后自动回切实时值；保持超过上限时间判定陈旧置状态码，供下游 PID/联锁在信号闪断期间平稳运行。边界：无载体（从未有效）=码03 拒绝输出；陈旧=码01 信息级；配置电平面=码02；载体锁存副本与透传镜像不混用。","双轨架构：_bHasLast 载体标志 + 锁存副本（失效期冻结）与透传镜像（有效期直通）严格二选一输出选择；tonStale 段 0 无条件刷新（R55）且 IN 条件含 NOT bSigOk AND _bHasLast 恢复自清零（R188）；三码分立（陈旧/配置/无载体）；与 FB_DL_AnalogSignalHealth（进侧诊断）互引分工。")),
 ("FB_DL_ImpulseRelay","DL_Base","FB",3,"OSCAT Basic 脉冲语义借鉴，clean-room 重写","classification","oscat-basic",["impulse","pulse","edge","one-shot","relay","oscat-basic","cleanroom","r67-new"],
  ("定宽脉冲继电器：输入信号出现上升沿后输出一个固定宽度脉冲（如 500ms 冲气阀/吹扫/计数脉冲），与输入宽度无关；重触发时重新计满全程脉宽。边界：脉宽配置<=0=码01 电平面故障不出脉冲；rtTrig/tonPulse 段 0 无条件刷新（R55）；重触发语义=边沿拍 IN 置 FALSE 重起计时（完整新脉宽）。","R_TRIG 沿捕获 + TON 定宽两实例架构，段 0 无条件刷新；脉冲展开用触发沿重置计时（非延续式），重触发即重启完整宽度；故障面（配置非法）拍不出脉冲并置码；与 FB_DL_PulseStretch（最小展宽保底）互引分工（固定宽度 vs 不足展宽）。")),
]

# 版本升级：name -> (new_version,)
BUMP = {"FC_DL_QuadPolyFit":"1.0.1", "FB_DL_LotMergeGate":"1.0.1", "FB_DL_TaktPaceMonitor":"1.0.2"}

now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
shutil.copy2(REG, BAK)
reg = json.load(io.open(REG, encoding="utf-8"))
comps = reg["components"]
by_name = {c["name"]: c for c in comps}

n_new = 0
for (n, cat, ty, cx, srcdesc, om, tag, tags, spec) in NEW:
    assert n not in by_name, "撞名: " + n
    p, src = st_read(cat, n)
    comps.append({
        "name": n, "category": cat, "type": ty, "file_path": p,
        "function_tags": tags, "complexity": cx, "version": "1.0.0",
        "registered_at": now, "line_count": src.count("\n") + 1,
        "code_segment": "", "source": "r67-plan",
        "origin": {"mode": om, "source": srcdesc, "license": "MIT" if om == "internal" else "cleanroom-ref",
                   "ref_tag": tag},
    })
    by_name[n] = comps[-1]
    n_new += 1

n_bump = 0
for n, v in BUMP.items():
    c = by_name[n]
    assert c["version"] != v, "版本未变: " + n
    c["version"] = v
    p, src = st_read(c["category"], n)
    c["line_count"] = src.count("\n") + 1
    c["updated_at"] = now
    n_bump += 1

cnt = {}
for c in comps:
    cnt[c["category"]] = cnt.get(c["category"], 0) + 1
reg["counts"] = cnt
reg["total_components"] = len(comps)
reg["version"] = "2.59.0"
reg["last_updated"] = now
assert sum(cnt.values()) == len(comps), "counts sum mismatch"
json.dump(reg, io.open(REG, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

def jsl_line(instr, at, src):
    return json.dumps({"instruction": instr, "architecture_thought": at, "output": src},
                      ensure_ascii=False, separators=(",", ":"))

added_new = added_re = 0
with io.open(JSL, "a", encoding="utf-8", newline="\n") as f:
    for (n, cat, ty, cx, srcdesc, om, tag, tags, spec) in NEW:
        instr, at = spec
        _, src = st_read(cat, n)
        f.write(jsl_line(instr, at, src) + "\n")
        added_new += 1
    # 返修重注入：找该组件最近一条既有语料，替换 output 为新版源码后追加
    for n in BUMP:
        cat = by_name[n]["category"]
        _, src = st_read(cat, n)
        found = None
        for ln in reversed(io.open(JSL, encoding="utf-8").readlines()):
            ln = ln.strip()
            if not ln or n not in ln:
                continue
            try:
                d = json.loads(ln)
                if n in d.get("output", ""):
                    found = d
                    break
            except Exception:
                continue
        assert found, "重注入找不到旧语料: " + n
        found["output"] = src
        f.write(jsl_line(found["instruction"], found["architecture_thought"], src) + "\n")
        added_re += 1

bad = tot = 0
for ln in io.open(JSL, encoding="utf-8"):
    ln = ln.strip()
    if not ln:
        continue
    tot += 1
    try:
        d = json.loads(ln)
        assert d.get("instruction") and d.get("architecture_thought") and d.get("output")
    except Exception:
        bad += 1
print("R67 closeout OK: new=%d bump=%d jsonl(+%d) registry=%d counts=%s lib=v2.59.0 jsonl_total=%d bad=%d"
      % (n_new, n_bump, added_new + added_re, len(comps), json.dumps(cnt, ensure_ascii=False), tot, bad))
