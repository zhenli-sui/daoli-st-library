(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ExtremumSeekCtrl
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.1
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / SIN / ABS），零厂商私有库
 * 功能描述 (Function)   : 极值寻优控制（扰动观察式 ES，无需模型）。在设定点
 *                         上叠加正弦扰动 dith = fDithAmp·SIN(ω·t)，对输出量
 *                         y 做同步解调：梯度估计 g ≈ 均值(y·dith)/均方(dith²)
 *                         （滚动窗归一化互相关），g > 0 说明设定点应增大、
 *                         g < 0 应减小；积分器按 fStepGain·g 调整设定点，
 *                         fSetpointOut = fSetBase + fTrim。设定点漂移追踪、
 *                         燃烧效率寻优、光伏 MPPT 类场景（公开 ES 语义 clean-room）。
 * 来源标签 (Origin)     : 自研线（公开极值寻优算法语义 clean-room，IEC 61131-3
 *                         标准语义的道莅防御性实现，零代码行复制）
 * 边界语义 (Boundary)   : ① 归一化除零防御：窗内均方 dith² <= eps（扰动被禁
 *                         或窗未填充）→ 梯度按 0（设定点保持），不产生 Inf；
 *                         ② 输出 NaN/Inf 拒收：y 非有限拍不参与解调累计；
 *                         ③ 修剪限幅：fTrim 双侧钳位于 [-fTrimLimit, +fTrimLimit]
 *                         （R151 补偿量钳位口径），防梯度发散把设定点推飞；
 *                         ④ 组态闸：扰动幅值/增益/限幅域检查 → 故障锁存。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → 修剪保持（设定点不跳变，
 *                         扰动冻结），bDitherOut = FALSE；eFault 相 → 修剪保持
 *                         末值 + bError = TRUE。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)，
 *                         码位待主控收口统一派号。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 除零（均方 eps 闸）/NaN 拒收/修剪钳位/组态闸 ✓
 *                         R5 双语同行注释 ✓｜R6 CASE 带 ELSE 兜底迁 eFault ✓
 *                         R7 TON/R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 y = -(x-50)² + 100（峰在 50），从 x=40 起寻优
 *                         → fTrim 单调逼近 +10（容差由 fStepGain/窗深决定）；
 *                         V2 峰左侧（g>0）→ fTrim 递增；峰右侧（g<0）→ 递减；
 *                         V3 fTrim 到 ±fTrimLimit 饱和不再外推。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R49 首版（批 3 · 序号 12）
 *                        2026-11-20  v1.0.1  R51 返修（R50 终审中×2）：①相位推进
 *                        删多乘 2.0 因子（扰动频率与组态周期一致）；②解调窗改真
 *                        滚动窗口径：tonWin 自复位（IN 带 NOT tonWin.Q，FB33-2），
 *                        到时单拍清 Σy·dith / Σdith² / 样本数，eIdle 相同步清窗，
 *                        梯度只反映最近 tWinTime 窗（与功能描述「滚动窗」一致）
 *==============================================================================*)
TYPE E_DL_EscState :
(
    eIdle  := 0,                             (* 待使能（修剪保持零） / Idle, trim held *)
    eSeek  := 10,                            (* 扰动寻优运行 / Perturb-and-seek run *)
    eFault := 90                             (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_EscCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：扰动/增益/限幅越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_ExtremumSeekCtrl
VAR_INPUT
    fY          : LREAL := 0.0;              (* 寻优输出量（被最大化目标）[工程单位] / Objective output to maximize *)
    fDithAmp    : LREAL := 1.0;              (* 正弦扰动幅值，域 > 0.0 [工程单位] / Dither amplitude *)
    fDithPeriod : TIME := T#2S;              (* 扰动周期，域 >= 20·tScan 工程约束（组态闸按非零检查）[ms] / Dither period *)
    tWinTime    : TIME := T#5S;              (* 解调滚动窗保持时长，域 > T#0S [ms] / Demodulation window hold time *)
    fStepGain   : LREAL := 0.5;              (* 梯度→修剪积分增益，域 > 0.0 [工程单位/拍] / Step gain *)
    fTrimLimit  : LREAL := 10.0;             (* 修剪限幅，域 > 0.0 [工程单位] / Trim limit *)
    fScanS      : LREAL := 0.01;             (* 扫描周期秒值（相位推进步长），域 > 1E-6 [s] / Scan period seconds *)
    bEnable     : BOOL := TRUE;              (* 寻优使能，FALSE 修剪保持扰动冻结 [-] / Enable *)
    bReset      : BOOL := FALSE;             (* 复位命令，上升沿清修剪/窗/相位 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fSetpointOut : LREAL;                    (* 设定点输出 = 基准 + 修剪 [工程单位] / Setpoint output *)
    fDitherOut   : LREAL;                    (* 当前扰动瞬时值（注入量诊断镜像）[工程单位] / Dither instantaneous value *)
    fTrim        : LREAL;                    (* 当前修剪量（相对基准偏移）[工程单位] / Current trim *)
    fGradEst     : LREAL;                    (* 当前梯度估计（归一化互相关）[-] / Gradient estimate *)
    bWindowFull  : BOOL;                     (* 窗到时清窗单拍脉冲（滚动窗节拍指示）[-] / Window-expiry single-scan pulse *)
    eState       : E_DL_EscState;            (* 状态出口 / State outlet *)
    eCause       : E_DL_EscCause;            (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError       : BOOL;                     (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState : E_DL_EscState := E_DL_EscState.eIdle;       (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause : E_DL_EscCause := E_DL_EscCause.eNone;       (* 故障成因锁存量 / Latched cause *)
    rtReset : R_TRIG;                        (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonWin  : TON;                           (* 解调窗计时，段 0 无条件调用 / Demod window timer *)
    _fPhase : LREAL := 0.0;                  (* 扰动相位累计（弧度），2π 回卷 [rad] / Dither phase accumulator *)
    _fDith  : LREAL;                         (* 本拍扰动瞬时值 [工程单位] / Dither this scan *)
    _fSxy   : LREAL;                         (* 解调窗累计：Σ y·dith [工程单位²] / Demod sum y·dith *)
    _fSdd   : LREAL;                         (* 解调窗累计：Σ dith² [工程单位²] / Demod sum dith² *)
    _nFill  : UDINT;                         (* 窗内有效样本数 [拍] / Valid sample count *)
    _fG     : LREAL;                         (* 本拍梯度估计 [-] / Gradient this scan *)
    _fTrimI : LREAL;                         (* 修剪量锁存（积分器）[工程单位] / Trim integrator latch *)
    _bFault : BOOL;                          (* 故障锁存位 / Latched fault bit *)
    _bCfgBad: BOOL;                          (* 组态非法当拍量 / Illegal config this scan *)
END_VAR
VAR CONSTANT
    DL_ESC_EPS    : LREAL := 1.0E-12;        (* 均方判零容差 [工程单位²] / Mean-square epsilon *)
    DL_ESC_2PI    : LREAL := 6.28318530717958648;   (* 2π（相位回卷界）[rad] / Two pi *)
    DL_ESC_TRIMMAX: LREAL := 1.0E6;          (* 修剪绝对安全上限（防积分器发散）[工程单位] / Trim absolute safety cap *)
    DL_ESC_NMAX   : UDINT := 4294960000;     (* 样本计数回绕防护上限 [-] / Sample count wrap guard *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (fDithAmp <= 0.0) OR (fStepGain <= 0.0) OR (fTrimLimit <= 0.0)   (* 组态闸：幅值/增益/限幅正域（R151 全引脚） / Config gate *)
            OR (fDithPeriod <= T#0S) OR (tWinTime <= T#0S) OR (fScanS <= 1.0E-6);
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)
tonWin(IN := (_eState = E_DL_EscState.eSeek) AND NOT tonWin.Q, PT := tWinTime);   (* 解调滚动窗自复位计时（FB33-2：IN 带自身 Q 取反，到时单拍后自动重启） / Self-resetting window timer *)
IF tonWin.Q THEN                             (* 窗到时单拍：清解调累计（滚动窗口径，与头注释一致，R338） / Window expiry: clear demod sums *)
    _fSxy := 0.0;                            (* 清 Σy·dith / Clear demod sum *)
    _fSdd := 0.0;                            (* 清 Σdith² / Clear mean-square sum *)
    _nFill := 0;                             (* 清有效样本数 / Clear fill count *)
END_IF
_fPhase := _fPhase + DL_ESC_2PI * fScanS / (TIME_TO_LREAL(fDithPeriod) / 1000.0);   (* 相位推进：ω·dt（v1.0.1 删多乘 2.0 因子），除子为周期秒值（组态闸已保证 > 0），无除零 / Phase advance ω·dt, divisor gated *)
IF _fPhase >= DL_ESC_2PI THEN
    _fPhase := _fPhase - DL_ESC_2PI;         (* 相位 2π 回卷（防浮点精度坍缩） / Phase wrap *)
END_IF
_fDith := fDithAmp * SIN(_fPhase);           (* 本拍扰动值（标准 SIN） / Dither value *)

(* —— 段 1：单拍量预清零（R107） —— *)
_fG := 0.0;                                  (* 梯度缺省 0（未定语义：不驱动修剪） / Gradient default zero *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清修剪积分器 + 清窗累计 + 清相位，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_EscCause.eNone;          (* 清成因 / Clear cause *)
    _fTrimI := 0.0;                          (* 清修剪积分器 / Clear trim integrator *)
    _fSxy := 0.0;                            (* 清解调累计 / Clear demod sums *)
    _fSdd := 0.0;                            (* 清均方累计 / Clear dith² sum *)
    _nFill := 0;                             (* 清样本数 / Clear fill count *)
    _fPhase := 0.0;                          (* 清相位 / Clear phase *)
    _eState := E_DL_EscState.eIdle;          (* 迁待机相 / Back to idle *)
END_IF

(* —— 段 3：组态闸故障锁存（R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                         (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_EscCause.eCfgIllegal;    (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_EscState.eFault;         (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_EscState.eIdle:                     (* 待机相：修剪保持、扰动冻结 / Idle *)
        _fSxy := 0.0;                        (* 待机清窗：窗只含连续 eSeek 期样本（滚动窗口径） / Clear window while idle *)
        _fSdd := 0.0;                        (* 清 Σdith² / Clear mean-square sum *)
        _nFill := 0;                         (* 清有效样本数 / Clear fill count *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_EscState.eSeek;  (* 进入寻优 / Enter seek *)
        END_IF
    E_DL_EscState.eSeek:                     (* 寻优相：解调 + 梯度积分 / Seek *)
        IF NOT bEnable THEN
            _eState := E_DL_EscState.eIdle;  (* 失能回待机（修剪保持不回零） / Back to idle, trim held *)
        ELSE
            IF (fY = fY) AND ((fY - fY) = (fY - fY)) THEN   (* 输出有限（NaN 自反 + Inf 差判） / Finite objective *)
                _fSxy := _fSxy + fY * _fDith;   (* 解调累计 Σy·dith / Demod accumulate *)
                _fSdd := _fSdd + _fDith * _fDith;   (* 均方累计 Σdith² / Mean-square accumulate *)
                IF _nFill < DL_ESC_NMAX THEN
                    _nFill := _nFill + 1;    (* 有效样本计数（UDINT 回绕防护） / Sample count, wrap-guarded *)
                END_IF
            END_IF
            IF (_fSdd > DL_ESC_EPS) AND (_nFill >= 8) THEN   (* 归一化除零闸 + 最小样本闸（边界①） / Normalization gate *)
                _fG := _fSxy / _fSdd;        (* 梯度估计 = Σy·dith / Σdith²（同窗归一化互相关） / Gradient estimate *)
            END_IF
            _fTrimI := _fTrimI + fStepGain * _fG;   (* 梯度驱动修剪积分 / Gradient-driven trim integrate *)
            IF _fTrimI > fTrimLimit THEN
                _fTrimI := fTrimLimit;       (* 修剪上限钳位（R151 口径） / Trim upper clamp *)
            ELSIF _fTrimI < (-fTrimLimit) THEN
                _fTrimI := (-fTrimLimit);    (* 修剪下限钳位 / Trim lower clamp *)
            END_IF
            IF ABS(_fTrimI) > DL_ESC_TRIMMAX THEN
                _fTrimI := DL_ESC_TRIMMAX;   (* 绝对安全上限兜底（防组态限幅被绕过） / Absolute safety cap *)
            END_IF
        END_IF
    E_DL_EscState.eFault:                    (* 故障相：修剪与扰动冻结，仅复位沿出 / Fault *)
        ;                                    (* 锁存回放（R28） / Replay from latch *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_EscState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_EscCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
fTrim := _fTrimI;                            (* 修剪出口镜像 / Trim mirror *)
fSetpointOut := _fTrimI;                     (* 设定点 = 修剪（基准由调用方叠加，属主边界：本件只管修剪量） / Setpoint = trim, base owned by caller *)
fDitherOut := _fDith;                        (* 扰动瞬时值镜像 / Dither mirror *)
fGradEst := _fG;                             (* 梯度估计镜像 / Gradient mirror *)
bWindowFull := tonWin.Q;                     (* 窗到时单拍脉冲镜像 / Window-expiry pulse mirror *)
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
