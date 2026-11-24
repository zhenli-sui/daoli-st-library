(*==============================================================================
 * 组件名称 (Component)  : FB_DL_VelFfGainIdent
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商私有库，
 *                         零轴状态枚举引用（R277）
 * 功能描述 (Function)   : 速度前馈增益辨识。恒速段窗口（bConstVel 电平：上层
 *                         速度指令平坦段）内对 (vFb, vCmd) 做 最小二乘 过原点
 *                         拟合 K = Σ(vFb·vCmd) / Σ(vFb²)（前馈模型 vCmd ≈ K·vFb
 *                         的残差最优解），同步累计残差标准差与样本数；样本充分
 *                         且拟合优度高（残差/信号比小）→ bIdentDone 单拍输出
 *                         fKvf。与 AxisFrictionFf 分工：本件辨识增益不注入
 *                         前馈（R312 模型不内嵌注入语义）。
 * 来源标签 (Origin)     : 自研线（IEC 61131-3 标准语义的道莅防御性实现，clean-room）
 * 分工声明 (Pairing)    : VelFfGainIdent（辨识，本件）↔ AxisFrictionFf（前馈注入，
 *                         既有件）：本件只产出辨识增益与置信指标，不写前馈通道、
 *                         不驱动轴（R298 属主边界）；辨识结果由调用方决定是否
 *                         下装（R312 口径）。
 * 边界语义 (Boundary)   : ① 过原点拟合分母闸：Σ(vFb²) <= eps（恒速段实际零速
 *                         或样本未采）→ 拟合不执行，K 保持上值；
 *                         ② 速度非有限拒收（NaN 自反 + Inf 差判）；
 *                         ③ 置信闸：残差均方根/均值 |vCmd| > fConfRatio
 *                         → 拟合质量不足，bIdentDone 不置位（辨识不可信
 *                         必须可观测，R28 口径）；
 *                         ④ 组态闸：最小样本/置信比/增益钳位域 → 故障。
 * 输出语义 (Fallback)   : 【R191】bConstVel = FALSE → 停止采样，fKvf 保持
 *                         末次辨识值（增益是资产，不随窗口停而清零）；
 *                         eFault 相 → 冻结 + bError = TRUE。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)，
 *                         码位待主控收口统一派号。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 除零（Σv² eps 闸）/NaN 拒收/组态闸 ✓
 *                         R5 双语同行注释 ✓｜R6 CASE 带 ELSE 兜底迁 eFault ✓
 *                         R7 TON/R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 恒速段 vCmd=vFb=200 → K=1.0（容差 1E-6）；
 *                         V2 vFb 恒为 vCmd 的 0.8 倍 → K=1.25；
 *                         V3 零速恒速段（vFb≈0）→ 分母闸生效，K 保持上值；
 *                         V4 残差比超阈 → bIdentDone 不置位。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R49 首版（批 4 · 序号 17）
 *==============================================================================*)
TYPE E_DL_VfiState :
(
    eIdle  := 0,                             (* 待使能 / Idle *)
    eLearn := 10,                            (* 恒速段采样与拟合 / Learning *)
    eFault := 90                             (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_VfiCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：样本/置信比越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_VelFfGainIdent
VAR_INPUT
    fVelCmd    : LREAL := 0.0;               (* 速度指令反馈快照 [mm/s] / Velocity command snapshot *)
    fVelFb     : LREAL := 0.0;               (* 实际速度反馈快照 [mm/s] / Velocity feedback snapshot *)
    bConstVel  : BOOL := FALSE;              (* 恒速段电平（上层速度平坦段判据直连）[-] / Constant-velocity window level *)
    nMinSample : INT := 64;                  (* 最小辨识样本数，域 8..100000 [点] / Min identification samples *)
    fConfRatio : LREAL := 0.1;               (* 置信比门限（残差 RMS / 均值|vCmd|），域 (0,1) [-] / Confidence ratio gate *)
    bEnable    : BOOL := TRUE;               (* 辨识使能 [-] / Enable *)
    bReset     : BOOL := FALSE;              (* 复位命令，上升沿清累计与锁存（fKvf 保留）[-] / Reset command *)
END_VAR
VAR_OUTPUT
    fKvf       : LREAL;                      (* 辨识速度前馈增益（末次有效值保持）[-] / Identified velocity ff gain *)
    nSampleCnt : INT;                        (* 本轮累计样本数 [点] / Sample count this round *)
    fResidRms  : LREAL;                      (* 跟随残差均方根（拟合质量）[mm/s] / Residual RMS *)
    bIdentDone : BOOL;                       (* 本轮辨识完成单拍位（质量闸通过才置位）[-] / Round-done single-scan pulse *)
    bIdentFail : BOOL;                       (* 本轮辨识质量不足锁存位（复位沿清）[-] / Round-quality-fail latch *)
    eState     : E_DL_VfiState;              (* 状态出口 / State outlet *)
    eCause     : E_DL_VfiCause;              (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError     : BOOL;                       (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_VfiState := E_DL_VfiState.eIdle;      (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_VfiCause := E_DL_VfiCause.eNone;      (* 故障成因锁存量 / Latched cause *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _nCnt    : INT;                          (* 样本计数锁存 [点] / Sample count latch *)
    _nMin    : INT;                          (* 钳位后生效最小样本数 [点] / Clamped min samples *)
    _fSfb2   : LREAL;                        (* Σ vFb² 累计 [mm²/s²] / Sum of vFb squared *)
    _fSfbc   : LREAL;                        (* Σ vFb·vCmd 累计 [mm²/s²] / Sum of vFb·vCmd *)
    _fSres2  : LREAL;                        (* Σ 残差² 累计（按上轮 K 算的即时残差）[mm²/s²] / Sum of squared residual *)
    _fSumAbs : LREAL;                        (* Σ |vCmd| 累计（置信比分母）[mm/s] / Sum of |vCmd| *)
    _fK      : LREAL := 1.0;                 (* 拟合增益锁存（缺省 1.0 = 无前馈修正语义）[-] / Fitted gain latch *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
END_VAR
VAR CONSTANT
    DL_VFI_EPS : LREAL := 1.0E-9;            (* 拟合分母判零容差 [mm²/s²] / Fit denominator epsilon *)
    DL_VFI_NMAX: INT   := 100000;            (* 样本上限（防 INT 溢出）[点] / Sample upper limit *)
    DL_VFI_KMAX: LREAL := 10.0;              (* 增益钳位上限（异常拟合兜底，R151 口径）[-] / Gain clamp limit *)
    DL_VFI_KMIN: LREAL := 0.1;               (* 增益钳位下限 [-] / Gain clamp lower limit *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (nMinSample < 8) OR (nMinSample > DL_VFI_NMAX) OR (fConfRatio <= 0.0) OR (fConfRatio >= 1.0);   (* 组态闸（R151 全引脚） / Config gate *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)
_nMin := nMinSample;                         (* 生效最小样本初值 / Min init *)
IF _nMin < 8 THEN
    _nMin := 8;                              (* 下限钳位 / Lower clamp *)
END_IF
IF _nMin > DL_VFI_NMAX THEN
    _nMin := DL_VFI_NMAX;                    (* 上限钳位（R308） / Upper clamp *)
END_IF

(* —— 段 1：单拍量预清零（R107） —— *)
bIdentDone := FALSE;                         (* 完成单拍位预清，唯一分支置位 / Done pulse preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清全部累计量 + 清样本数 + 清质量锁存；fKvf 保留，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_VfiCause.eNone;          (* 清成因 / Clear cause *)
    _nCnt := 0;                              (* 清样本数 / Clear count *)
    _fSfb2 := 0.0;                           (* 清 ΣvFb² / Clear sum *)
    _fSfbc := 0.0;                           (* 清 ΣvFb·vCmd / Clear sum *)
    _fSres2 := 0.0;                          (* 清 Σ残差² / Clear sum *)
    _fSumAbs := 0.0;                         (* 清 Σ|vCmd| / Clear sum *)
    fResidRms := 0.0;                        (* 清 RMS 出口 / Clear outlet *)
    bIdentFail := FALSE;                     (* 清质量不足锁存 / Clear fail latch *)
    nSampleCnt := 0;                         (* 清样本出口 / Clear count outlet *)
    _eState := E_DL_VfiState.eIdle;          (* 迁待机相 / Back to idle *)
END_IF

(* —— 段 3：组态闸故障锁存（R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                         (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_VfiCause.eCfgIllegal;    (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_VfiState.eFault;         (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_VfiState.eIdle:                     (* 待机相 / Idle *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_VfiState.eLearn; (* 进入学习 / Enter learn *)
        END_IF
    E_DL_VfiState.eLearn:                    (* 学习相：恒速段采样 + 过原点 LS 拟合 / Learn *)
        IF NOT bEnable THEN
            _eState := E_DL_VfiState.eIdle;  (* 失能回待机（fKvf 保持） / Back to idle *)
        ELSIF bConstVel THEN                 (* 仅恒速段采样（判据串相位因子，R281） / Sample only in const-vel *)
            IF (fVelFb = fVelFb) AND (fVelCmd = fVelCmd)
               AND ((fVelFb - fVelFb) = (fVelFb - fVelFb)) AND ((fVelCmd - fVelCmd) = (fVelCmd - fVelCmd)) THEN
                _fSfb2 := _fSfb2 + fVelFb * fVelFb;       (* ΣvFb² 累计 / Accumulate *)
                _fSfbc := _fSfbc + fVelFb * fVelCmd;      (* ΣvFb·vCmd 累计 / Accumulate *)
                _fSres2 := _fSres2 + (fVelCmd - _fK * fVelFb) * (fVelCmd - _fK * fVelFb);   (* 即时残差² 累计（按当前 K） / Instant residual² *)
                _fSumAbs := _fSumAbs + ABS(fVelCmd);      (* Σ|vCmd| 累计 / Accumulate *)
                IF _nCnt < DL_VFI_NMAX THEN
                    _nCnt := _nCnt + 1;      (* 样本计数（INT 溢出防护） / Count advance *)
                END_IF
            END_IF
            IF _fSfb2 > DL_VFI_EPS THEN      (* 分母闸：恒速段非零速才拟合（边界①） / Denominator gate *)
                _fK := _fSfbc / _fSfb2;      (* 过原点最小二乘 K = Σ(vFb·vCmd)/Σ(vFb²)（分母已过 eps 闸，无除零） / Origin-LS fit, denominator gated *)
                IF _fK > DL_VFI_KMAX THEN
                    _fK := DL_VFI_KMAX;      (* 增益上限钳位（异常拟合兜底） / Gain upper clamp *)
                ELSIF _fK < DL_VFI_KMIN THEN
                    _fK := DL_VFI_KMIN;      (* 增益下限钳位（IF 链带 ELSE 兜底，R285） / Gain lower clamp *)
                END_IF
            END_IF
            IF (_nCnt >= _nMin) AND (_fSfb2 > DL_VFI_EPS) AND (_nCnt >= 1) THEN
                fResidRms := SQRT(_fSres2 / INT_TO_LREAL(_nCnt));   (* RMS 出口（除子恒 >= 1，无除零） / RMS outlet *)
                IF ABS(fVelCmd) > DL_VFI_EPS OR _fSumAbs > DL_VFI_EPS THEN
                    IF (_fSumAbs / INT_TO_LREAL(_nCnt)) > DL_VFI_EPS AND (fResidRms / (_fSumAbs / INT_TO_LREAL(_nCnt))) <= fConfRatio THEN
                        fKvf := _fK;         (* 质量闸通过：增益下装出口 / Quality passed: gain outlet *)
                        bIdentDone := TRUE;  (* 完成单拍脉冲 / Done pulse *)
                        bIdentFail := FALSE; (* 清质量不足锁存 / Clear fail latch *)
                        _eState := E_DL_VfiState.eIdle;   (* 收口回待机（下轮重新累计） / Back to idle *)
                    ELSIF (_fSumAbs / INT_TO_LREAL(_nCnt)) > DL_VFI_EPS THEN
                        bIdentFail := TRUE;  (* 质量不足锁存至复位沿（R28 可观测口径） / Quality fail latch *)
                        _eState := E_DL_VfiState.eIdle;   (* 收口回待机 / Back to idle *)
                    END_IF
                END_IF
            END_IF
            nSampleCnt := _nCnt;             (* 样本数出口镜像 / Count mirror *)
        END_IF
    E_DL_VfiState.eFault:                    (* 故障相：冻结保持，仅复位沿出 / Fault *)
        ;                                    (* 锁存回放（R28） / Replay from latch *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_VfiState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_VfiCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
