(*==============================================================================
 * 组件名称 (Component)  : FB_DL_LoopCoupleDetect
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.1
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 回路耦合度在线探测。本回路上位激励期（bExcite 电平）
 *                         同步采集本回路 CV 增量 x 与邻回路 PV 增量 y，窗口内
 *                         计算皮尔逊互相关系数 r；|r| >= fCoupleThresh 且样本
 *                         充分 → bCoupled 锁存并输出耦合强度分级。为 Decouple2x2
 *                         提供投运判据（探测在先、解耦执行在后）。
 * 来源标签 (Origin)     : 自研线（IEC 61131-3 标准语义的道莅防御性实现，clean-room）
 * 分工声明 (Pairing)    : LoopCoupleDetect（探测，本件）↔ FB_DL_Decouple2x2
 *                         （解耦执行，既有件）：本件只输出耦合判据与强度分级，
 *                         不注入任何解耦补偿量、不修改解耦矩阵（R298 属主边界）；
 *                         与 FB_DL_CrossCorrelationDelay 分工：本件测「响应强度」
 *                         不测「延时幅值」，二者互补不重叠。
 * 边界语义 (Boundary)   : ① 相关系数除零防御：任一分母因子 <= eps → r 按 0
 *                         （邻回路无响应 = 无耦合语义，合法结果非故障）；
 *                         ② 非激励期（bExcite = FALSE）不采样不判据（判据串
 *                         相位因子，R281 口径）；
 *                         ③ 增量非有限拒收（NaN 自反 + Inf 差判）；
 *                         ④ 组态闸：窗深/阈值/最小样本 → 故障锁存。
 * 输出语义 (Fallback)   : 【R191】非激励期 → fCorrOut 保持末值、bCoupled 保持
 *                         锁存（耦合是资产属性，不随激励停而消失）；eFault 相
 *                         → 冻结 + bError = TRUE。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)，
 *                         码位待主控收口统一派号。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 除零（双因子 eps 闸）/NaN 拒收/组态闸 ✓
 *                         R5 双语同行注释 ✓｜R6 CASE 带 ELSE 兜底迁 eFault ✓
 *                         R7 TON/R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 强耦合仿真（y = 0.8·x + 噪声）→ |r| ≈ 0.8+，
 *                         eStrength=eStrong，bCoupled=TRUE；
 *                         V2 独立回路（y 与 x 无关）→ |r| < 阈值，
 *                         eStrength=eNone；
 *                         V3 非激励期停止采样，样本数不增。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R49 首版（批 3 · 序号 13）
 *                        2026-11-20  v1.0.1  R51 文档级更正（R50 终审轻项）：3 处
 *                        相对指代禁词注释改为自含描述（R92/R68）；逻辑零变更
 *==============================================================================*)
TYPE E_DL_LcdStrength :
(
    eNone    := 0,                           (* 无耦合：|r| < 弱阈值 / No coupling *)
    eWeak    := 1,                           (* 弱耦合：|r| ∈ [弱阈, 强阈) / Weak coupling *)
    eStrong  := 2                            (* 强耦合：|r| >= 强阈值 / Strong coupling *)
);
END_TYPE

TYPE E_DL_LcdState :
(
    eIdle  := 0,                             (* 待使能 / Idle *)
    eProbe := 10,                            (* 激励探测运行 / Excitation probing *)
    eFault := 90                             (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_LcdCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：窗深/阈值越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_LoopCoupleDetect
VAR_INPUT
    fCvThis   : LREAL := 0.0;                (* 本回路 CV 当前值（激励侧）[工程单位] / This loop CV value *)
    fPvNeighbor : LREAL := 0.0;              (* 邻回路 PV 当前值（响应侧）[工程单位] / Neighbor loop PV value *)
    bExcite   : BOOL := FALSE;               (* 本回路激励期电平（上位投运流程给出）[-] / Excitation period level *)
    nWinDepth : INT := 64;                   (* 互相关窗深，域 8..128 [点] / Correlation window depth *)
    fCoupleThresh : LREAL := 0.5;            (* 耦合判据阈值（|r| 门限），域 (0,1) [-] / Coupling threshold *)
    bEnable   : BOOL := TRUE;                (* 探测使能 [-] / Enable *)
    bReset    : BOOL := FALSE;               (* 复位命令，上升沿清窗与全部锁存 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fCorrOut  : LREAL;                       (* 当前窗口互相关系数 [-] / Window correlation coefficient *)
    eStrength : E_DL_LcdStrength;            (* 耦合强度分级出口（按最新窗口派生）[-] / Coupling strength outlet *)
    bCoupled  : BOOL;                        (* 耦合判据锁存位（复位沿清）[-] / Coupled latch *)
    nSampleCnt: INT;                         (* 窗口有效样本数 [点] / Valid sample count *)
    eState    : E_DL_LcdState;               (* 状态出口 / State outlet *)
    eCause    : E_DL_LcdCause;               (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError    : BOOL;                        (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_LcdState := E_DL_LcdState.eIdle;      (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_LcdCause := E_DL_LcdCause.eNone;      (* 故障成因锁存量 / Latched cause *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _fCvPrev : LREAL;                        (* 上拍本回路 CV（增量基准）[工程单位] / Previous this-loop CV *)
    _fPvPrev : LREAL;                        (* 上拍邻回路 PV（增量基准）[工程单位] / Previous neighbor PV *)
    _aDx     : ARRAY[1..128] OF LREAL;       (* 本回路 CV 增量窗 [工程单位] / This-loop dCV window *)
    _aDy     : ARRAY[1..128] OF LREAL;       (* 邻回路 PV 增量窗 [工程单位] / Neighbor dPV window *)
    _nHead   : INT;                          (* 环形头游标 [-] / Ring head cursor *)
    _nFill   : INT;                          (* 窗填充数 [点] / Window fill count *)
    _nEff    : INT;                          (* 钳位后生效窗深 [点] / Clamped effective depth *)
    _fSumX   : LREAL;                        (* Σx [工程单位] / Sum x *)
    _fSumY   : LREAL;                        (* Σy [工程单位] / Sum y *)
    _fSumXY  : LREAL;                        (* Σxy [工程单位²] / Sum xy *)
    _fSumX2  : LREAL;                        (* Σx² [工程单位²] / Sum x2 *)
    _fSumY2  : LREAL;                        (* Σy² [工程单位²] / Sum y2 *)
    _fDen    : LREAL;                        (* 分母乘积（开方前）[-] / Denominator product *)
    _fR      : LREAL;                        (* 本拍相关系数 [-] / Correlation this scan *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _i       : INT;                          (* 统计扫描游标（每趟重置，R227）[-] / Stats cursor *)
END_VAR
VAR CONSTANT
    DL_LCD_EPS  : LREAL := 1.0E-12;          (* 分母因子判零容差 [-] / Denominator epsilon *)
    DL_LCD_NMAX : INT   := 128;              (* 窗深容量上限 [点] / Window capacity limit *)
    DL_LCD_MIN  : INT   := 16;               (* 判据最小样本数（不足不判，防短窗误报）[点] / Min samples for verdict *)
    DL_LCD_WEAK : LREAL := 0.3;              (* 弱耦合门限（强度分级内界）[-] / Weak coupling bound *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (nWinDepth < 8) OR (nWinDepth > DL_LCD_NMAX) OR (fCoupleThresh <= 0.0) OR (fCoupleThresh >= 1.0);   (* 组态闸（R151 全引脚） / Config gate *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)
_nEff := nWinDepth;                          (* 生效窗深初值 / Depth init *)
IF _nEff < 8 THEN
    _nEff := 8;                              (* 下限钳位 / Lower clamp *)
END_IF
IF _nEff > DL_LCD_NMAX THEN
    _nEff := DL_LCD_NMAX;                    (* 上限钳位（R308） / Upper clamp *)
END_IF

(* —— 段 1：单拍量预清零（R107） —— *)
_fSumX := 0.0;                               (* 累计量清零重算（每拍全路径派生，R285） / Sums recompute *)
_fSumY := 0.0;                               (* Σy 清零 / Sum y clear *)
_fSumXY := 0.0;                              (* Σxy 清零 / Sum xy clear *)
_fSumX2 := 0.0;                              (* Σx² 清零 / Sum x2 clear *)
_fSumY2 := 0.0;                              (* Σy² 清零 / Sum y2 clear *)
_fDen := 0.0;                                (* 分母清零（防残留触发除零） / Denominator clear *)
_fR := 0.0;                                  (* 相关系数缺省 0 / Correlation default *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清窗 + 清锁存 + 基准重锚 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_LcdCause.eNone;          (* 清成因 / Clear cause *)
    _nFill := 0;                             (* 清窗填充 / Clear fill *)
    _nHead := 1;                             (* 头游标复位 / Head reset *)
    bCoupled := FALSE;                       (* 清耦合锁存 / Clear coupled latch *)
    fCorrOut := 0.0;                         (* 清相关系数出口 / Clear correlation outlet *)
    _fCvPrev := fCvThis;                     (* 增量基准重锚 / Re-anchor base *)
    _fPvPrev := fPvNeighbor;                 (* 邻回路 PV 增量基准重锚 / Re-anchor neighbor PV base *)
    _eState := E_DL_LcdState.eIdle;          (* 迁待机相 / Back to idle *)
END_IF

(* —— 段 3：组态闸故障锁存（R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                         (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_LcdCause.eCfgIllegal;    (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_LcdState.eFault;         (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_LcdState.eIdle:                     (* 待机相：基准持续跟锚 / Idle *)
        _fCvPrev := fCvThis;                 (* 防待机期巨增量 / Anchor follow *)
        _fPvPrev := fPvNeighbor;             (* 邻回路 PV 基准持续跟锚（防待机期巨增量） / Neighbor PV base follow *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_LcdState.eProbe; (* 进入探测 / Enter probe *)
        END_IF
    E_DL_LcdState.eProbe:                    (* 探测相：仅激励期采样 + 窗口统计 / Probe *)
        IF NOT bEnable THEN
            _eState := E_DL_LcdState.eIdle;  (* 失能回待机 / Back to idle *)
        ELSE
            IF bExcite THEN                  (* 判据串相位因子：仅激励期采样（R281） / Sample only in excitation *)
                _aDx[_nHead] := fCvThis - _fCvPrev;       (* 本回路 CV 增量入窗 / This-loop dCV *)
                _aDy[_nHead] := fPvNeighbor - _fPvPrev;   (* 邻回路 PV 增量入窗 / Neighbor dPV *)
                IF (_aDx[_nHead] <> _aDx[_nHead]) OR (_aDy[_nHead] <> _aDy[_nHead])
                   OR ((_aDx[_nHead] - _aDx[_nHead]) <> (_aDx[_nHead] - _aDx[_nHead]))
                   OR ((_aDy[_nHead] - _aDy[_nHead]) <> (_aDy[_nHead] - _aDy[_nHead])) THEN
                    (* 非有限增量：不入统计不推进游标，基准照常跟锚 / Non-finite: skip *)
                    ;                        (* 空语句：ST 语法要求 THEN 分支非空，无副作用 / Empty statement, ST syntax requires non-empty branch *)
                ELSE
                    _nHead := _nHead + 1;    (* 有效样本：游标递进 / Head advance *)
                    IF _nHead > _nEff THEN
                        _nHead := 1;         (* 环回卷 / Ring wrap *)
                    END_IF
                    IF _nFill < _nEff THEN
                        _nFill := _nFill + 1;    (* 填充封顶 / Fill cap *)
                    END_IF
                END_IF
                _fCvPrev := fCvThis;         (* 基准推进 / Base advance *)
                _fPvPrev := fPvNeighbor;     (* 邻回路 PV 基准推进（与本拍采样配对） / Neighbor PV base advance *)
            END_IF
            _i := 1;                         (* 统计游标起头重置（R227） / Cursor reset *)
            WHILE _i <= _nFill DO            (* 逐点累计 / Per-point sums *)
                _fSumX := _fSumX + _aDx[_i]; (* Σx / Sum x *)
                _fSumY := _fSumY + _aDy[_i]; (* Σy / Sum y *)
                _fSumXY := _fSumXY + _aDx[_i] * _aDy[_i];   (* Σxy / Sum xy *)
                _fSumX2 := _fSumX2 + _aDx[_i] * _aDx[_i];   (* Σx² / Sum x2 *)
                _fSumY2 := _fSumY2 + _aDy[_i] * _aDy[_i];   (* Σy² / Sum y2 *)
                _i := _i + 1;                (* 游标递进 / Cursor advance *)
            END_WHILE
            IF _nFill >= 1 THEN
                _fDen := (DINT_TO_LREAL(_nFill) * _fSumX2 - _fSumX * _fSumX)
                       * (DINT_TO_LREAL(_nFill) * _fSumY2 - _fSumY * _fSumY);   (* 分母乘积（双因子联合闸） / Denominator product *)
            END_IF
            IF (_fDen > DL_LCD_EPS * DL_LCD_EPS) AND (_nFill >= 1) THEN
                _fR := (DINT_TO_LREAL(_nFill) * _fSumXY - _fSumX * _fSumY) / SQRT(_fDen);   (* 互相关 r：分母已过联合 eps 闸，无除零 / Correlation, denominator gated *)
                fCorrOut := _fR;             (* 相关系数出口更新（仅有效窗刷新） / Update outlet *)
                IF (_nFill >= DL_LCD_MIN) AND (_nFill * 10 >= 6 * _nEff) THEN
                    IF ABS(_fR) >= fCoupleThresh THEN
                        bCoupled := TRUE;    (* 耦合判据锁存至复位沿 / Coupled latch *)
                    END_IF
                    IF ABS(_fR) >= fCoupleThresh THEN
                        eStrength := E_DL_LcdStrength.eStrong;   (* 强耦合 / Strong *)
                    ELSIF ABS(_fR) >= DL_LCD_WEAK THEN
                        eStrength := E_DL_LcdStrength.eWeak;     (* 弱耦合 / Weak *)
                    ELSE
                        eStrength := E_DL_LcdStrength.eNone;     (* 无耦合（IF 链带 ELSE 兜底，R285） / None *)
                    END_IF
                END_IF
            END_IF
            nSampleCnt := _nFill;            (* 样本数出口镜像 / Sample count mirror *)
        END_IF
    E_DL_LcdState.eFault:                    (* 故障相：冻结保持，仅复位沿出 / Fault *)
        ;                                    (* 锁存回放（R28） / Replay from latch *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_LcdState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_LcdCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
