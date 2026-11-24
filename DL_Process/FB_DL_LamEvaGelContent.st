(*==============================================================================
 * 组件名称 (Component)  : FB_DL_LamEvaGelContent
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 层压 EVA 交联度估算与合格窗判定。三段工艺换算：
 *                         ① 温度-时间积分 ∫max(0, T - Tref)dt（有效热剂量，
 *                         [°C·min]）；② 线性标定曲线 gel = fGelBase + fKRate·
 *                         Dose（[%]）；③ 合格窗 [fGelLo, fGelHi] 判定。层压
 *                         运行电平控制积分启停。与 Integrator（纯积分）分工：
 *                         本件是积分→标定→判窗三段工艺换算。
 * 来源标签 (Origin)     : ROADMAP §19.2 R12 池（L814），自研 clean-room
 * 边界语义 (Boundary)   : ① 首扫初始化 _bInit（R310：积分类件首拍清剂量）；
 *                         ② 温度 NaN/Inf 拍冻结积分（不累计不判窗）；
 *                         ③ 交联度换算后域钳 [0, 100]（标定外推过冲钳位）；
 *                         ④ 组态闸：基准温度/速率/窗界/扫描秒值域检查 → 故障。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → 积分冻结保持（剂量与交联
 *                         度为资产属性）；eFault 相 → 冻结 + bError = TRUE。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 除零无涉/NaN 冻结/钳位/组态闸 ✓｜R5 双语同行注释 ✓
 *                         R6 CASE 带 ELSE 兜底迁 eFault ✓｜R7 R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 T=150 恒定、Tref=140、fScanS=1.0、fKRate=0.02：
 *                         600 s 后 Dose = 600·10/60 = 100 [°C·min]，
 *                         gel = 基准 20 + 0.02·100 = 22.0 [%]；
 *                         V2 T <= Tref 全程 → Dose=0，gel=基准（不超下界）；
 *                         V3 gel > 100 外推过冲 → 钳 100（边界③）。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R51 首版（批 2 · 序号 10）
 *==============================================================================*)
TYPE E_DL_LgcState :
(
    eIdle  := 0,                             (* 待使能 / Idle *)
    eCalc  := 10,                            (* 积分与判窗运行 / Calc run *)
    eFault := 90                             (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_LgcCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：基准/速率/窗界越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_LamEvaGelContent
VAR_INPUT
    fTempC    : LREAL := 25.0;               (* 层压温度 [°C] / Lamination temperature *)
    fTempRef  : LREAL := 140.0;              (* 交联基准温度（低于不累计），域 > 0 [°C] / Reference temperature *)
    fKRate    : LREAL := 0.02;               (* 标定斜率，域 > 0 [%/(°C·min)] / Calibration rate *)
    fGelBase  : LREAL := 20.0;               (* 交联度基准截距，域 [0,100] [%] / Base gel content *)
    fGelLo    : LREAL := 75.0;               (* 合格窗下限，域 < fGelHi [%] / Gel window lower *)
    fGelHi    : LREAL := 95.0;               (* 合格窗上限，域 > fGelLo [%] / Gel window upper *)
    fScanS    : LREAL := 1.0;                (* 扫描周期秒值，域 > 1E-6 [s] / Scan period seconds *)
    bProcRun  : BOOL := FALSE;               (* 层压运行电平（积分启停）[-] / Process run level *)
    bEnable   : BOOL := TRUE;                (* 使能 [-] / Enable *)
    bReset    : BOOL := FALSE;               (* 复位命令，上升沿清剂量与输出 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fDose     : LREAL;                       (* 有效热剂量 [°C·min] / Effective thermal dose *)
    fGelPct   : LREAL;                       (* 交联度估算（钳 0..100）[%] / Gel content estimate *)
    bGelOk    : BOOL;                        (* 合格窗判定（窗口内）[-] / Gel-in-window verdict *)
    eState    : E_DL_LgcState;               (* 状态出口 / State outlet *)
    eCause    : E_DL_LgcCause;               (* 故障成因出口 / Fault cause outlet *)
    bError    : BOOL;                        (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_LgcState := E_DL_LgcState.eIdle;      (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_LgcCause := E_DL_LgcCause.eNone;      (* 故障成因锁存量 / Latched cause *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _fDose   : LREAL;                        (* 剂量积分锁存 [°C·min] / Dose integrator latch *)
    _fGel    : LREAL;                        (* 交联度派生量 [%] / Gel derived *)
    _bTempBad: BOOL;                         (* 温度非有限当拍量 [-] / Non-finite temperature *)
    _bInit   : BOOL := FALSE;                (* 首扫初始化标志（R310）[-] / First-scan init flag *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
END_VAR
VAR CONSTANT
    DL_LGC_EPS : LREAL := 1.0E-6;            (* 秒值判零容差 [s] / Seconds epsilon *)
    DL_LGC_MIN : LREAL := 60.0;              (* 秒 → 分换算常量 [s/min] / Seconds per minute *)
    DL_LGC_GMAX: LREAL := 100.0;             (* 交联度物理上限 [%] / Gel physical max *)
    DL_LGC_INF : LREAL := 1.0E30;            (* Inf 差判兜底量纲界 [—] / Inf diff guard *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (fTempRef <= 0.0) OR (fKRate <= 0.0) OR (fGelBase < 0.0) OR (fGelBase > DL_LGC_GMAX)
            OR (fGelLo >= fGelHi) OR (fScanS <= DL_LGC_EPS);   (* 组态闸（R151 全引脚 + 窗界序） / Config gate *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)
_bTempBad := (fTempC <> fTempC) OR ((fTempC - fTempC) <> (fTempC - fTempC))
            OR (ABS(fTempC) > DL_LGC_INF);   (* 温度 NaN 自反 + Inf 差判 + 量纲兜底 / Non-finite temperature *)

(* —— 段 1：首扫初始化（R310：积分类件首拍清剂量，与复位沿同款） —— *)
IF NOT _bInit THEN
    _fDose := 0.0;                           (* 首拍剂量清零 / First-scan dose clear *)
    _fGel := fGelBase;                       (* 首拍交联度取基准 / First-scan gel base *)
    _bInit := TRUE;                          (* 置初始化完成 / Set init done *)
END_IF
_fGel := 0.0;                                (* 交联度当拍量预清（每拍全路径派生，R285） / Gel preset *)
bGelOk := FALSE;                             (* 判窗预清（全路径赋值） / Verdict preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清剂量积分 + 清输出 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_LgcCause.eNone;          (* 清成因 / Clear cause *)
    _fDose := 0.0;                           (* 清剂量积分 / Clear dose *)
    fDose := 0.0;                            (* 清剂量出口 / Clear dose outlet *)
    fGelPct := fGelBase;                     (* 交联度回基准 / Gel back to base *)
    _eState := E_DL_LgcState.eIdle;          (* 迁待机相 / Back to idle *)
END_IF

(* —— 段 3：组态闸故障锁存（R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                         (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_LgcCause.eCfgIllegal;    (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_LgcState.eFault;         (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_LgcState.eIdle:                     (* 待机相 / Idle *)
        IF bEnable AND NOT _bFault AND NOT _bTempBad THEN
            _eState := E_DL_LgcState.eCalc;  (* 进入计算 / Enter calc *)
        END_IF
    E_DL_LgcState.eCalc:                     (* 计算相：积分 + 标定 + 判窗 / Calc *)
        IF NOT bEnable THEN
            _eState := E_DL_LgcState.eIdle;  (* 失能回待机（剂量冻结保持，R191 声明） / Back to idle, dose held *)
        ELSIF bProcRun AND (NOT _bTempBad) THEN   (* 运行电平 + 温度有限才积分 / Integrate when running *)
            IF fTempC > fTempRef THEN        (* 有效热剂量：仅高于基准累计 / Dose above reference *)
                _fDose := _fDose + (fTempC - fTempRef) * fScanS / DL_LGC_MIN;   (* 增量 = ΔT·dt/60 [°C·min]，除子常量 60 无除零 / Dose increment *)
            END_IF
        END_IF                               (* 温度坏值/停运拍：积分冻结（边界②） / Freeze on bad temp *)
        _fGel := fGelBase + fKRate * _fDose; (* 标定曲线换算（乘法无除零） / Calibration transform *)
        IF _fGel < 0.0 THEN
            _fGel := 0.0;                    (* 下界钳位 / Lower clamp *)
        ELSIF _fGel > DL_LGC_GMAX THEN
            _fGel := DL_LGC_GMAX;            (* 上界钳位（外推过冲兜底，边界③） / Upper clamp *)
        END_IF
        IF (_eState = E_DL_LgcState.eCalc) AND (NOT _bTempBad) THEN   (* 判窗仅运行域有效拍 / Verdict in valid scans *)
            fDose := _fDose;                 (* 剂量出口刷新 / Dose outlet *)
            fGelPct := _fGel;                (* 交联度出口刷新 / Gel outlet *)
            IF _fGel < fGelLo THEN
                bGelOk := FALSE;             (* 低于窗 / Below window *)
            ELSIF _fGel > fGelHi THEN
                bGelOk := FALSE;             (* 高于窗 / Above window *)
            ELSE
                bGelOk := TRUE;              (* 窗内（IF 链带 ELSE 兜底，R285） / In window *)
            END_IF
        END_IF
    E_DL_LgcState.eFault:                    (* 故障相：冻结保持，仅复位沿出 / Fault *)
        ;                                    (* 锁存回放（R28） / Replay from latch *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_LgcState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_LgcCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
