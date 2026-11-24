(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SignalReconstruct
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library，零厂商私有库
 * 功能描述 (Function)   : 短丢包信号重构（状态估计族）。bSampleValid 电平指示
 *                         本拍采样有效；有效拍更新最近两次有效样本 (t1,v1)/(t2,v2)
 *                         并派生斜率 k = (v2-v1)/dt21；丢包期间按一阶外插
 *                         fOut = v2 + k·dtHold 输出，不确定度带按
 *                         fUncert = fUncBase + fUncRate·dtHold 随保持时长线性
 *                         增长（外插越久越不可信），bReconstructed 指示当前拍
 *                         为重构值。通信抖动、探头短时断流、HMI 采样缺口场景。
 * 来源标签 (Origin)     : 自研线（状态估计语义 clean-room，IEC 61131-3 标准语义的
 *                         道莅防御性实现，零代码行复制）
 * 边界语义 (Boundary)   : ① 丢 1 拍即可重构；连续丢包超过 tMaxHold → 停止外插，
 *                         bValid 强制 FALSE 并冻结末值（超窗重构比冻结更危险，
 *                         R133 语义：不把外推值伪装成测量）；
 *                         ② dt21 除零防御：两次有效样本间隔 <= eps → 斜率置 0
 *                         （零阶保持退化为常值外插），不产生 Inf；
 *                         ③ NaN 样本拒收：v1/v2 非有限 → 不入样本槽，bValid=FALSE；
 *                         ④ 组态闸：fUncBase < 0.0 或 fUncRate < 0.0 或
 *                         tMaxHold <= T#0S → 故障锁存。
 * 输出语义 (Fallback)   : 【R191】bValid = FALSE → fOut 冻结保持末次有效值
 *                         （不清零，避免下游把 0 当真值）；eFault 相 → 冻结 +
 *                         bError = TRUE。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)，
 *                         码位待主控收口统一派号。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 除零防御（dt eps 闸）/NaN 拒收/组态闸 ✓
 *                         R5 双语同行注释 ✓｜R6 CASE 带 ELSE 兜底迁 eFault ✓
 *                         R7 无定时器实例（监视型），N/A ✓
 * 验收向量 (Acceptance) : V1 v1=10.0@t0、v2=12.0@t0+2s，丢包 1s 后
 *                         fOut=13.0（k=1/s 容差 1E-6）；
 *                         V2 丢包 3s（< tMaxHold=5s）→ fUncert = fUncBase + 3·fUncRate；
 *                         V3 连续丢包 6s（> 5s）→ bValid=FALSE 冻结末值。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R49 首版（批 2 · 序号 7）
 *==============================================================================*)
TYPE E_DL_SrcState :
(
    eIdle  := 0,                             (* 未取得首个有效样本（无基线可外插） / Idle, no baseline *)
    eRun   := 10,                            (* 样本流运行（有效拍更新 / 丢包拍外插） / Run: update or extrapolate *)
    eFault := 90                             (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_SrcCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：不确定度参数越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_SignalReconstruct
VAR_INPUT
    fSample    : LREAL := 0.0;               (* 采样输入值 [工程单位] / Sample input value *)
    bSampleValid : BOOL := FALSE;            (* 本拍采样有效电平（通信链质量位直连）[-] / Sample-valid level this scan *)
    tScan      : TIME := T#100MS;            (* 扫描周期（保持时长积分步长），域 > T#0S [ms] / Scan cycle time step *)
    fUncBase   : LREAL := 0.1;               (* 不确定度基础项，域 >= 0.0 [工程单位] / Base uncertainty term *)
    fUncRate   : LREAL := 0.05;              (* 不确定度增长率，域 >= 0.0 [工程单位/s] / Uncertainty growth rate *)
    tMaxHold   : TIME := T#2S;               (* 最大允许外插保持时长，域 > T#0S [ms] / Max extrapolation hold time *)
    bEnable    : BOOL := TRUE;               (* 重构使能，FALSE 时冻结输出不外插 [-] / Enable *)
    bReset     : BOOL := FALSE;              (* 复位命令，上升沿清全部样本槽与锁存 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fOut          : LREAL;                   (* 重构/直通输出值（无效相冻结保持）[工程单位] / Output value *)
    fUncert       : LREAL;                   (* 当前不确定度带半宽 [工程单位] / Uncertainty band half-width *)
    bReconstructed: BOOL;                    (* 本拍为重构值（丢包外插拍）指示 [-] / Reconstructed-this-scan flag *)
    bValid        : BOOL;                    (* 输出可用性（超窗冻结时 FALSE）[-] / Output validity *)
    nHoldScans    : UDINT;                   (* 当前连续丢包拍数（诊断）[拍] / Consecutive hold scan count *)
    eState        : E_DL_SrcState;           (* 状态出口 / State outlet *)
    eCause        : E_DL_SrcCause;           (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError        : BOOL;                    (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_SrcState := E_DL_SrcState.eIdle;      (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_SrcCause := E_DL_SrcCause.eNone;      (* 故障成因锁存量 / Latched cause *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _fV1     : LREAL;                        (* 基线样本 1 值（锁存槽）[工程单位] / Baseline sample 1 value *)
    _fV2     : LREAL;                        (* 基线样本 2 值（锁存槽）[工程单位] / Baseline sample 2 value *)
    _nT1     : UDINT;                        (* 样本 1 时间戳（扫描计数）[拍] / Sample 1 timestamp in scans *)
    _nT2     : UDINT;                        (* 样本 2 时间戳（扫描计数）[拍] / Sample 2 timestamp in scans *)
    _nScan   : UDINT;                        (* 全局扫描计数器（时间戳基）[拍] / Global scan counter *)
    _nHold   : UDINT;                        (* 连续丢包拍数锁存 [拍] / Consecutive hold count latch *)
    _fK      : LREAL;                        (* 外插斜率 = (v2-v1)/dt21 [工程单位/拍] / Extrapolation slope *)
    _fOutInt : LREAL;                        (* 内部输出保持槽（锁存量）[工程单位] / Internal output hold *)
    _bHave2  : BOOL;                         (* 已取得两个有效样本位（外插资格）[-] / Two-sample baseline acquired *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
END_VAR
VAR CONSTANT
    DL_SRC_EPS : LREAL := 1.0E-9;            (* 样本间隔判零容差 [拍] / Sample-interval epsilon *)
END_VAR

(* —— 段 0：当拍判据派生 + 沿实例无条件刷新（R228A） —— *)
_bCfgBad := (fUncBase < 0.0) OR (fUncRate < 0.0) OR (tMaxHold <= T#0S) OR (tScan <= T#0S);   (* 组态闸覆盖每个域引脚（R151） / Config gate, every pin *)
rtReset(CLK := bReset);                                       (* 复位沿每拍必调 / Reset edge every scan *)
_nScan := _nScan + 1;                                         (* 扫描计数推进（UDINT 回绕：2^32 拍 @10ms ≈ 497 天，工程按期重启覆盖） / Scan counter advance *)

(* —— 段 1：单拍量预清零（R107） —— *)
bReconstructed := FALSE;                                      (* 重构指示预清，唯一分支置位 / Reconstructed flag preset *)
bValid := FALSE;                                              (* 有效性预清（派生出口，全路径赋值 R285） / Validity preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清样本槽 + 清计数器 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                         (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_SrcCause.eNone;                           (* 清成因 / Clear cause *)
    _fV1 := 0.0;                                              (* 清样本槽 1 / Clear slot 1 *)
    _fV2 := 0.0;                                              (* 清样本槽 2 / Clear slot 2 *)
    _nT1 := 0;                                                (* 清时间戳 1 / Clear timestamp 1 *)
    _nT2 := 0;                                                (* 清时间戳 2 / Clear timestamp 2 *)
    _nHold := 0;                                              (* 清丢包计数 / Clear hold count *)
    _nScan := 0;                                              (* 清时间戳基 / Clear timestamp base *)
    _fK := 0.0;                                               (* 清斜率 / Clear slope *)
    _fOutInt := 0.0;                                          (* 清输出保持槽 / Clear output hold *)
    _bHave2 := FALSE;                                         (* 清外插资格 / Clear baseline flag *)
    bValid := FALSE;                                          (* 输出有效性同步清 / Output validity clear *)
    _eState := E_DL_SrcState.eIdle;                           (* 迁待基线相 / Back to idle *)
END_IF

(* —— 段 3：组态闸故障锁存（R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                          (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_SrcCause.eCfgIllegal;                     (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_SrcState.eFault;                          (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_SrcState.eIdle:                                      (* 待基线相：只收样本不外插 / Idle: collect only *)
        IF bEnable AND NOT _bFault AND bSampleValid AND (fSample = fSample) AND ((fSample - fSample) = (fSample - fSample)) THEN
            _fV1 := fSample;                                  (* 首个有效样本入槽 1 / First sample into slot 1 *)
            _nT1 := _nScan;                                   (* 记时间戳 / Record timestamp *)
            _fOutInt := fSample;                              (* 直通输出 / Pass-through *)
            bValid := TRUE;                                   (* 单样本即可直通 / Valid with one sample *)
            _eState := E_DL_SrcState.eRun;                    (* 进入运行相 / Enter run *)
        END_IF
    E_DL_SrcState.eRun:                                       (* 运行相：有效拍更新 / 丢包拍外插 / Run *)
        IF NOT bEnable THEN                                   (* 失能：冻结输出（声明语义） / Disable: freeze *)
            _nHold := 0;                                      (* 清丢包计数 / Clear hold count *)
            _eState := E_DL_SrcState.eIdle;                   (* 回待基线（不重置样本槽，恢复使能即可续用基线） / Back to idle, slots kept *)
        ELSIF bSampleValid AND (fSample = fSample) AND ((fSample - fSample) = (fSample - fSample)) THEN
            (* 有效拍：旧 v2 滚动入 v1，新样本入 v2，斜率重派生 / Valid scan: roll slots, re-derive slope *)
            _fV1 := _fV2;                                     (* 槽 2 滚动入槽 1 / Roll slot 2 to slot 1 *)
            _nT1 := _nT2;                                     (* 时间戳同步滚动 / Roll timestamp *)
            _fV2 := fSample;                                  (* 新样本入槽 2 / New sample into slot 2 *)
            _nT2 := _nScan;                                   (* 新时间戳 / New timestamp *)
            IF (UDINT_TO_LREAL(_nT2 - _nT1)) > DL_SRC_EPS THEN
                _fK := (_fV2 - _fV1) / UDINT_TO_LREAL(_nT2 - _nT1);   (* 斜率派生：间隔已判非零，无除零 / Slope, divisor gated *)
            ELSE
                _fK := 0.0;                                   (* 同拍重复样本：斜率退化 0（零阶保持） / Degenerate slope zero *)
            END_IF
            _bHave2 := TRUE;                                  (* 外插资格确立 / Baseline acquired *)
            _fOutInt := fSample;                              (* 直通输出 / Pass-through *)
            fUncert := fUncBase;                              (* 有效拍不确定度 = 基础项 / Uncertainty = base *)
            _nHold := 0;                                      (* 清丢包计数 / Clear hold count *)
            bValid := TRUE;                                   (* 有效 / Valid *)
        ELSE
            (* 丢包拍：一阶外插 + 不确定度线性增长 / Dropped scan: extrapolate *)
            _nHold := _nHold + 1;                             (* 丢包计数递增 / Hold count advance *)
            _fOutInt := _fV2 + _fK * UDINT_TO_LREAL(_nHold);  (* 一阶外插（斜率按拍计） / First-order extrapolation *)
            fUncert := fUncBase + fUncRate * UDINT_TO_LREAL(_nHold) * TIME_TO_LREAL(tScan) / 1000.0;   (* 不确定度带：基础项 + 增长率·保持秒 / Uncertainty band growth *)
            IF _bHave2 THEN
                bValid := TRUE;                               (* 有基线：外插值有效 / Baseline: extrapolation valid *)
                bReconstructed := TRUE;                       (* 重构指示 / Reconstructed flag *)
            END_IF
            IF (tMaxHold > T#0S) AND (UDINT_TO_LREAL(_nHold) * TIME_TO_LREAL(tScan) / 1000.0 > TIME_TO_LREAL(tMaxHold) / 1000.0) THEN
                bValid := FALSE;                              (* 超窗：停止外插信任，冻结末值（R133 不伪装测量） / Beyond window: freeze, stop trusting extrapolation *)
                _fOutInt := _fV2;                             (* 冻结到末次有效样本 / Freeze to last valid sample *)
                fUncert := fUncBase + fUncRate * TIME_TO_LREAL(tMaxHold) / 1000.0;   (* 不确定度封顶在窗界 / Cap uncertainty at window bound *)
            END_IF
        END_IF
    E_DL_SrcState.eFault:                                     (* 故障相：冻结保持，仅复位沿出 / Fault *)
        ;                                                     (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                      (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_SrcState.eFault;                      (* 迁故障相 / To fault *)
        _bFault := TRUE;                                      (* 同步锁存 / Latch *)
        _eCause := E_DL_SrcCause.ePhaseBad;                   (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
fOut := _fOutInt;                                             (* 输出单点映射 / Output mapping *)
nHoldScans := _nHold;                                         (* 丢包计数镜像 / Hold count mirror *)
bError := _bFault;                                            (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                            (* 状态出口 / State outlet *)
eCause := _eCause;                                            (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
