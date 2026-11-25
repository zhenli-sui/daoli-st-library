# -*- coding: utf-8 -*-
# R78 closeout: registry + JSONL append + three-way count check
import json, os, io

TS = "2026-11-23T23:52:00+08:00"
REG = "INDEX_REGISTRY.json"
JL = "_AI_Training_Dataset/daoli_st_sft_dataset.jsonl"

# name -> (category, ftype, complexity, tags, zh_desc, instruction_scenario)
ITEMS = {
 "FC_DL_CharIsDigit":("DL_MathData","FC",2,["char","classify","digit","validation"],"单字符判十进制数字","配料屏手动输入的批号字符逐位校验：判断 STRING(1) 单字符是否为 0~9，空串与非 ASCII 输入一律返回 FALSE"),
 "FC_DL_CharIsAlpha":("DL_MathData","FC",2,["char","classify","alpha","validation"],"单字符判英文字母","操作员姓名首字符校验：判断单字符是否为 A~Z/a~z，数字与符号返回 FALSE"),
 "FC_DL_CharIsAlnum":("DL_MathData","FC",2,["char","classify","alnum","validation"],"单字符判字母或数字","物料条码段合法性校验：字母或数字通过，其余（含空格/符号）拒绝"),
 "FC_DL_CharIsUpper":("DL_MathData","FC",2,["char","classify","uppercase","validation"],"单字符判大写字母","配方代号大写规范检查：A~Z 通过，小写/数字/符号不通过"),
 "FC_DL_CharIsLower":("DL_MathData","FC",2,["char","classify","lowercase","validation"],"单字符判小写字母","日志标签小写规范检查：a~z 通过，其余不通过"),
 "FC_DL_CharIsSpace":("DL_MathData","FC",2,["char","classify","whitespace","validation"],"单字符判空白（空格/Tab）","HMI 输入去空白预处理：识别空格 32 与 Tab 9，其余返回 FALSE"),
 "FC_DL_CharIsHexDigit":("DL_MathData","FC",2,["char","classify","hex","validation"],"单字符判十六进制位","Modbus 报文人读化校验：0~9/A~F/a~f 通过，用于地址与 CRC 展示字段"),
 "FC_DL_CharToUpper":("DL_MathData","FC",2,["char","convert","uppercase"],"小写转大写（其余原样）","批次号统一大写规整：a~z 映射 A~Z，非小写字符原样返回，便于不区分大小写比对"),
 "FC_DL_ParityEvenByte":("DL_Base","FC",2,["parity","checksum","byte","serial"],"字节偶校验位","串口 8N1 改 8E1 通信适配：对 BYTE 逐位折叠计算偶校验位"),
 "FC_DL_ParityOddByte":("DL_Base","FC",2,["parity","checksum","byte","serial"],"字节奇校验位","8O1 串口仪表对接：对 BYTE 计算奇校验位，与偶校验件极性互补"),
 "FC_DL_ParityEvenWord":("DL_Base","FC",2,["parity","checksum","word","serial"],"字偶校验位","16 位帧校验位生成：WORD 逐位折叠偶校验"),
 "FC_DL_ParityOddWord":("DL_Base","FC",2,["parity","checksum","word","serial"],"字奇校验位","16 位帧奇校验位生成：WORD 极性相反口径"),
 "FC_DL_ParityEvenLword":("DL_Base","FC",2,["parity","checksum","dword","serial"],"双字偶校验位（32 位 DWORD 口径，头注声明）","32 位帧校验位：DWORD 逐位折叠偶校验（件名 Lword 实为 32 位实现，口径见头注）"),
 "FC_DL_ParityOddLword":("DL_Base","FC",2,["parity","checksum","dword","serial"],"双字奇校验位（32 位 DWORD 口径，头注声明）","32 位帧奇校验位：DWORD 极性相反口径"),
 "FC_DL_RoundToMultipleReal":("DL_MathData","FC",2,["rounding","multiple","real","alignment"],"实数四舍五入到 N 的倍数（N<=0 返 0）","卷径/料位按 0.5mm 刻度对齐显示：fX 对齐到 fM 的倍数，fM<=0 返 0 防除零"),
 "FC_DL_CeilToMultipleInt":("DL_MathData","FC",2,["rounding","multiple","ceil","alignment"],"整数向上对齐 N 倍数（带 DINT 溢出饱和闸）","托盘整箱数向上取整：nX 向上对齐到 nM 倍数，进位前反算 2147483647-nM 防回绕"),
 "FC_DL_FloorToMultipleInt":("DL_MathData","FC",2,["rounding","multiple","floor","alignment"],"整数向下对齐 N 倍数（带 DINT 溢出饱和闸）","整箱裁剪数向下取整：nX 向下对齐 nM 倍数，退位前反算防负回绕"),
 "FC_DL_TruncToMultipleInt":("DL_MathData","FC",2,["rounding","multiple","trunc","alignment"],"整数截断到 N 倍数","整除余料清零：nX 截断到 nM 倍数，nM<=0 返 0"),
 "FC_DL_ForceUnitConvert":("DL_MathData","FC",2,["unit-convert","force","engineering"],"N/kN/lbf 力单位互转（枚举源/目标，CASE ELSE 返 0）","压装机压力设定在公制/英制 HMI 间切换：E_DL 枚举源目标单位换算，越界枚举返 0"),
 "FC_DL_TimeUnitConvert":("DL_MathData","FC",2,["unit-convert","time","engineering"],"s/min/h 时间单位互转（枚举源/目标）","节拍报表秒/分/时口径统一：枚举源目标换算，越界 CASE ELSE 返 0"),
 "FC_DL_BcdIsValidByte":("DL_MathData","FC",2,["bcd","validation","byte"],"判字节是否合法 BCD","拨码开关输入合法性：每半字节 <=9 才合法，非法返回 FALSE"),
 "FC_DL_BcdIsValidWord":("DL_MathData","FC",2,["bcd","validation","word"],"判字是否合法 BCD","四位拨码盘整字校验：WORD 每半字节 <=9"),
 "FC_DL_BcdAddByte":("DL_MathData","FC",2,["bcd","arithmetic","byte","saturate"],"两位 BCD 加法（溢出饱和 99 置错）","拨码设定值累加：BCD 域内加法，非法输入置错不写回，结果 >99 饱和 99"),
 "FC_DL_BcdSubByte":("DL_MathData","FC",2,["bcd","arithmetic","byte","saturate"],"两位 BCD 减法（借位下溢饱和 0 置错）","拨码设定值递减：BCD 域内减法，下溢饱和 0 并置错"),
 "FC_DL_BcdIncrementByte":("DL_MathData","FC",2,["bcd","arithmetic","byte","counter"],"BCD 字节加 1（99 进位回 0）","班次计数拨码轮：99 后回 00 循环"),
 "FC_DL_BcdDecrementByte":("DL_MathData","FC",2,["bcd","arithmetic","byte","counter"],"BCD 字节减 1（0 借位回 99）","倒计时拨码轮：00 后回 99 循环"),
 "FC_DL_RateLimitReal":("DL_MathData","FC",2,["rate-limit","slew","real","slew"],"REAL 单拍斜率限幅（fRateMax/fDt 越域旁路，fXPrev 经 VAR_IN_OUT 重建）","阀门开度指令限速：超速按 fRateMax*fDt 逼近；速率/周期<=0 旁路；fXPrev 非有限时以本拍输入重建并置 ePrevRebuilt 信息码"),
 "FC_DL_RampStepReal":("DL_MathData","FC",2,["ramp","step","real"],"固定步长爬坡（fStep<=0 直跳目标）","变频器频率每拍最多走 fStep 软启动：不足一步直接到达，fStep<=0 直跳目标"),
 "FC_DL_SlewLimitLreal":("DL_MathData","FC",2,["rate-limit","slew","lreal"],"LREAL 精度斜率限幅（REAL 窄化饱和出口，R10 显式转换）","高精度温控设定限速：全链 LREAL，输出窄化 REAL 时饱和防溢出"),
 "FC_DL_DeltaClampReal":("DL_MathData","FC",2,["delta-clamp","increment","real"],"相邻两拍增量钳位（|Δ|>fMaxDelta 按方向钳位）","电子凸轮随动指令平滑：单拍增量超限按方向钳位后叠加"),
 "FC_DL_SaturateIncr":("DL_MathData","FC",2,["saturate","increment","arithmetic"],"原地递增饱和（超上限饱和上限，低于下限抬升）","整定参数在线步进微调：x+1 越上限饱和，低于下限抬升到下限"),
 "FC_DL_SaturateDecr":("DL_MathData","FC",2,["saturate","decrement","arithmetic"],"原地递减饱和（低于下限饱和下限，高于上限压回）","整定参数在线步进微调反向：x-1 越下限饱和"),
 "FC_DL_AccelUnitConvert":("DL_MathData","FC",2,["unit-convert","acceleration","engineering"],"加速度单位互转 m/s²↔g（g0=9.80665，CASE ELSE 返 0）","振动监测加速度计 g 与 SI 口径切换"),
 "FC_DL_DynViscosityUnitConvert":("DL_MathData","FC",2,["unit-convert","viscosity","dynamic"],"动力粘度 cP↔Pa·s↔mPa·s（1 cP≡1 mPa·s，负值拒收返 0）","涂料/胶粘度工艺口径切换；与运动粘度件（ViscosityUnitConvert）物理量不同、分工互补"),
 "FC_DL_FlowMassUnitConvert":("DL_MathData","FC",2,["unit-convert","mass-flow","engineering"],"质量流量 kg/h↔t/h↔lb/h（反向流合法，与体积流量件分工）","蒸汽/粉体质量流量报表口径切换"),
 "FB_DL_MultiZoneSetpointScheduler":("DL_Process","FB",4,["process","setpoint","scheduler","time-window","state-machine","fault-latch"],"多区（4 区×8 时段）设定值按日时段表切换，含非单调校验闸、eHold 重校验闸、钳位信息码防覆盖与故障锁存回放","多温区烤炉按日时段表自动切换设定值：4 区各 8 时段（起始分钟+设定值），eApply 校验时段非单调/设定值非有限即锁存 eFault；eHold 执行相每拍重校验条数引脚（外部可变）防越界；边界：时段跨午夜不支持、分钟域 [0,1439]、钳位发生时保留 eMinuteClamped 诊断码不被成功路径覆盖"),
 "FB_DL_WinderTensionTaperCalc":("DL_Motion","FB",4,["motion","winder","tension","taper","state-machine"],"收卷 3 段折线锥度张力计算（节点 0/1/3、2/3、1），卷径无效即撤张力并锁存","收卷张力随卷径锥度递减：三段折线插值计算张力设定，上下限钳位；卷径 <=0 或 > 最大卷径 → eFault 锁存、张力输出 0；与线性锥度件 WinderTensionTaperCtrl 分工（本件为分段折线）"),
 "FB_DL_AnalogSensorHealthClassify":("DL_Device","FB",4,["device","analog","health","classify","statistics"],"模拟量通道健康分级（滑动窗 μ/σ²/极值 → 正常·卡滞·超量程上/下·噪声，含置信码）","模拟量通道自诊断：滑动窗统计均值/方差/极值，判卡滞（σ² 持续低于阈值）、超量程上/下、噪声过大；采样数 <1 走 eNoSample 哨兵防除零；与 AnalogSignalHealth（4-20mA/NE43 断线）分工"),
 "FB_DL_PalletizerLayerBuildSeq":("DL_Process","FB",4,["process","palletizer","layer-seq","state-machine","timeout"],"码垛层构建时序（取—放—满层—换层—满垛，相超时兜底 + 单拍层完成沿）","码垛机器人层构建时序：eIdle/ePick/ePlace/eLayerDone/eFull/eFault 状态机，R_TRIG 取放沿计数（初值 FALSE 防首拍误触发），相超时 TON 周期刷新兜底转 eFault，bReset 沿复位；与 PalletizerLayerSeq/PalletizerStation 分工"),
}

ORIGIN_INTERNAL = {"mode":"internal","source":"道莅原创（自研线）","license":"MIT"}
ORIGIN_DERIVED = {"mode":"derived","source":"fisothemes/TwinCAT-Dynamic-String-Kit (MIT) 语义溯源 clean-room","license":"MIT","url":"https://github.com/fisothemes/TwinCAT-Dynamic-String-Kit","ref_tag":"char-classify"}

def arch(fn, it):
    cat, ftype, cx, tags, zh, ins = it
    if ftype == "FC":
        return ("纯函数无状态设计：全部防御闸前置（非法输入按契约返 0/FALSE，不静默纠正），除法/对齐前做 N<=0 与溢出反算守卫；"
                "数学核心与输入闸分离，便于向量复验；REAL/LREAL 精度链全显式 *_TO_* 转换（R10），无 TRUNC/构造函数式转换；"
                "无 GVL、无 %I/%Q，纯 IEC 61131-3 跨平台语法，错误路径与正常路径单出口返回。")
    return ("ENUM 状态机 + CASE 分派 + ELSE 兜底：eFault 锁存经唯一复位沿（bReset R_TRIG + NOT 使能）回 eIdle，故障成因枚举 latch 回放；"
            "TON 相超时在 CASE 外无条件周期刷新，相切换拍 IN 自清（相位快照口径）；外部引脚在执行相逐拍重校验（防中间可变引脚越界）；"
            "沿计数 R_TRIG 初值 FALSE 防首拍误触发；钳位/降级走独立信息码不被成功路径覆盖；"
            "与库内并行件（同名近邻）头注声明分工边界，零职责重叠；数据访问全部定长数组显式界闸，无 VLA 透传。")

reg = json.load(io.open(REG, encoding="utf-8"))
comps = reg["components"]
reg_names = {c["name"] for c in comps}

adds = []
for name, it in ITEMS.items():
    cat, ftype, cx, tags, zh, ins = it
    if name in reg_names:
        print("SKIP registered:", name); continue
    path = os.path.join("C:\\Library", cat, name + ".st")
    if not os.path.exists(path):
        print("MISSING FILE:", name); continue
    origin = ORIGIN_DERIVED if name.startswith("FC_DL_Char") else ORIGIN_INTERNAL
    entry = {"name": name, "category": cat, "type": ftype, "file_path": path,
             "function_tags": tags + (["oscat-semantic"] if origin["mode"]=="derived" else []),
             "complexity": cx, "registered_at": TS, "origin": origin, "l2_status": "l2-pass"}
    adds.append((entry, name, zh, ins, ftype))

with io.open(JL, "a", encoding="utf-8") as f:
    for entry, name, zh, ins, ftype in adds:
        src = io.open(entry["file_path"], encoding="utf-8").read()
        rec = {"instruction": f"【{zh}】工况：{ins}。边界条件：所有非法/越界/非有限输入按契约安全出口，不静默纠正、不回绕、不除零。",
               "architecture_thought": arch(name, ITEMS[name]),
               "output": src}
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")

for entry, *_ in adds:
    comps.append(entry)

reg["total_components"] = len(comps)
reg["last_updated"] = TS
reg["version"] = "2.70.0"
from collections import Counter
cnt = Counter(c["category"] for c in comps)
reg["counts"] = {k: cnt[k] for k in ["DL_Base","DL_MathData","DL_Algo","DL_Device","DL_Motion","DL_Process"]}
json.dump(reg, io.open(REG, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

st_files = sum(1 for c in ["DL_Base","DL_MathData","DL_Algo","DL_Device","DL_Motion","DL_Process"] for f in os.listdir(c) if f.endswith(".st"))
jl_lines = sum(1 for _ in io.open(JL, encoding="utf-8"))
print("registry:", reg["total_components"], "counts:", reg["counts"], "sum:", sum(reg["counts"].values()))
print("st files:", st_files, "jsonl:", jl_lines, "adds:", len(adds))
print("MATCH" if (reg["total_components"]==st_files) else "DIFF registry vs st:", reg["total_components"]-st_files, "jsonl vs st:", jl_lines-st_files)
