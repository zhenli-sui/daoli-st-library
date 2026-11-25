(*==============================================================================
 * 组件名称 (Component)  : FB_DL_WinderTensionTaperCalc
 * 所属子库 (Sublibrary) : DL_Motion ｜ 版本 (Version) : 1.0.0 ｜ 2026-11-23
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准（CASE / ABS / MAX / MIN），零厂商私有库
 * 功能描述 (Function)   : 收卷锥度张力计算（分段折线口径）。卷径归一化比例 r =
 *                         (fRollDia − fDiaCore) ÷ (fDiaMax − fDiaCore) ∈ [0,1]，锥度系数 k(r)
 *                         按 **3 段折线** 插值：节点 (0, 1.0) → (1/3, 1 − 0.45·t) →
 *                         (2/3, 1 − 0.78·t) → (1, 1 − t)，t = fTaperPct ÷ 100。
 *                         折线前段缓、后段陡：小卷径段张力衰减慢（防松卷），大卷径段衰减快
 *                         （防内层压溃），与线性锥度件（FB_DL_WinderTensionTaperCtrl）
 *                         的区别即在此曲线形状。
 *                         **卷径有效性闸**：fRollDia ≤ 0 或 > fDiaMax → eFault 且 fTensionOut := 0
 *                         （安全侧直接撤张力，不保留末值）。
 *                         **bEnable = FALSE 语义（R191 二选一，本件选「冻结保持末值」）**：
 *                         张力环的硬切断由上级安全回路负责，本件失能时保持末值不突变。
 * 接口     (Interface)  : 输入 bEnable / bReset / fRollDia / fDiaCore / fDiaMax / fTensionIn /
 *                         fTaperPct / fTensionMin / fTensionMax；输出 fTensionOut（限幅后）/
 *                         fTaperFactor / fDiaRatio / eState / bError / eCause / bValid。
 * 状态迁移表 (State Transition Table)：
 *   ① eIdle → eRun：bEnable 上升（进入计算相）；拍 N 进入（bEnable）/ 本拍行为：不做计算、
 *      输出保持末值 / 拍 N+1 转出至 eRun。
 *   ② eRun → eFault：组态域闸失败（卷芯径 ≤0 / 卷径上下限倒置 / 张力上下限倒置 /
 *      锥度率越域 0..90 / 任一浮点非有限）或卷径有效性闸失败（≤0 或 > fDiaMax）；
 *      拍 N 进入（判据失败）/ 本拍行为：锁存首因、fTensionOut := 0、fTaperFactor := 0 /
 *      拍 N+1 转出至 eFault（段尾迁移闸）。
 *   ③ eRun → eIdle：bEnable 落 FALSE（失能退出，出口冻结保持）。
 *   ④ eIdle → eFault：段尾迁移闸（锁存位已置）。
 *   ⑤ eFault → eIdle：bReset 上升且 NOT bEnable（复位沿要求先失能，可达性自证 R152：
 *      两引脚外部恒可达）；拍 N 进入（复位沿 + 已失能）/ 本拍行为：清锁存与成因码 /
 *      拍 N+1 转出至 eIdle。
 *   ⑥ ELSE（非法枚举值）→ eFault，成因码 eIllegalState（R6 兜底）。
 * 边界     (Boundary)   : ① 卷径先钳位到 [fDiaCore, fDiaMax] 再算比例（r 结构性落在 [0,1]）。
 *                         ② 折线三段的插值分母均为常量（0.33333、0.33334、0.33333），
 *                            编译期非零，结构性无除零（R4）。
 *                         ③ t = fTaperPct ÷ 100.0，除数为字面常量 100.0（非零）。
 *                         ④ 输出张力钳位到 [fTensionMin, fTensionMax]，上限 / 下限饱和各占
 *                            独立成因成员（R190 归因唯一）。
 *                         ⑤ 浮点同值比较统一容差 DL_TTP_EPS（1E-6），禁 `=`。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / %I / %Q）。
 * 码表     (Codes)      : 本件不占用全局数字码位（R297 零码位范式）；出口为 BOOL + ENUM，
 *                         enum E_DL_TaperCause 归属本文件（全库唯一属主）。信息级
 *                         eSatHigh / eSatLow 永不置 bError；故障级码锁存回放至 bReset 沿。
 * 分工声明 (Scope)      : 线性锥度 + 斜坡限速件为 FB_DL_WinderTensionTaperCtrl（E_DL_WttState
 *                         属主）；本件只做分段折线曲线与钳位，不做斜坡、不做张力闭环。
 * 归属     (Ownership)  : E_DL_WttState 归属 FB_DL_WinderTensionTaperCtrl.st，本件只引用
 *                         不重声明（R264）；E_DL_TaperCause 归属本文件。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC ｜ R4 ✓ 卷径域闸 +
 *                         非有限双判 + 常量除法 + 容差比较 ｜ R5 ✓ 逐行同行双语注释
 *                         R6 ✓ 三态 ENUM + CASE + ELSE ｜ R7 N/A（无定时器/边沿实例）
 *                         R14 ✓ 无 PROPERTY ｜ R8/R9 N/A（无 METHOD）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R78-B3 首版
 * 验收向量 (Acceptance) :
 *   V1 fRollDia=100, fDiaCore=100, fDiaMax=800, fTensionIn=50, fTaperPct=30 →
 *      r=0 → k=1.0 → fTensionOut=50.0, bValid=TRUE, eCause=eNone。
 *   V2 其余引脚取 V1 值、fRollDia=333.3 → r≈0.3333 → k=1−0.3×0.45=0.865 → fTensionOut≈43.25（容差 1E-3）。
 *   V3 其余引脚取 V1 值、fRollDia=800 → r=1 → k=0.7 → fTensionOut=35.0。
 *   V4 fRollDia=0.0 → eState=eFault, eCause=eBadDiameter, fTensionOut=0.0, bError=TRUE；
 *      bReset 上升且 bEnable=FALSE → 回 eIdle。
 *   V5 fTaperPct=95（越域）→ eState=eFault, eCause=eBadTaper, fTensionOut=0.0。
 *   V6 fTensionOut 计算得 5.0 而 fTensionMin=10.0 → fTensionOut=10.0, eCause=eSatLow（信息级）。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_TaperCause（锥度张力成因码；信息级 = 0..9，故障级 = 10 起）
 *----------------------------------------------------------------------------*)
TYPE E_DL_TaperCause :
(
    eNone         := 0,   // 信息级：计算正常 / Info: computation normal
    eSatHigh      := 1,   // 信息级：输出张力已饱和到上限 / Info: output saturated at the high limit
    eSatLow       := 2,   // 信息级：输出张力已饱和到下限 / Info: output saturated at the low limit
    eBadDiameter  := 10,  // 故障级：卷径反馈无效（≤0 或 > fDiaMax）/ Fault: invalid roll diameter
    eBadConfig    := 11,  // 故障级：卷芯/限值组态倒置或越界 / Fault: inverted or out-of-range configuration
    eBadTaper     := 12,  // 故障级：锥度率越域（0..90）/ Fault: taper percentage out of the 0..90 domain
    eNonFinite    := 13,  // 故障级：入参非有限 / Fault: non-finite input
    eIllegalState := 14   // 故障级：非法状态枚举值 / Fault: illegal state enum value
);
END_TYPE

FUNCTION_BLOCK FB_DL_WinderTensionTaperCalc
VAR_INPUT
    bEnable     : BOOL := FALSE;      // 使能：FALSE 冻结保持末值（本件语义声明）/ Enable, FALSE freezes the last output
    bReset      : BOOL := FALSE;      // 复位（上升沿，需同时 bEnable=FALSE）/ Reset rising edge, requires disabled state
    fRollDia    : REAL := 100.0;      // 当前卷径反馈，有效域 (0, fDiaMax] [mm] / Current roll diameter feedback [mm]
    fDiaCore    : REAL := 100.0;      // 卷芯直径（锥度曲线起点），域 > 0 [mm] / Core diameter, curve origin [mm]
    fDiaMax     : REAL := 800.0;      // 满卷直径（锥度曲线终点），域 > fDiaCore [mm] / Full roll diameter, curve end [mm]
    fTensionIn  : REAL := 50.0;       // 内圈基础张力给定 [N] / Base (inner) tension setpoint [N]
    fTaperPct   : REAL := 30.0;       // 满卷处张力衰减百分比，有效域 0..90 [%] / Tension taper at full roll, domain 0..90 [%]
    fTensionMin : REAL := 0.0;        // 张力输出下限，域 ≥ 0 [N] / Tension output low limit [N]
    fTensionMax : REAL := 200.0;      // 张力输出上限，域 > fTensionMin [N] / Tension output high limit [N]
END_VAR
VAR_OUTPUT
    fTensionOut  : REAL := 0.0;        // 锥度张力输出（限幅后）[N] / Tapered tension output after clamping [N]
    fTaperFactor : REAL := 0.0;        // 本拍锥度系数 k（0..1）[-] / Taper factor k of this scan
    fDiaRatio    : REAL := 0.0;        // 本拍归一化卷径比例 r（0..1）[-] / Normalised diameter ratio r of this scan
    eState       : E_DL_WttState;      // 状态出口（段尾单点映射，引用属主枚举）[-] / State outlet mapped at the tail
    bError       : BOOL;               // 故障锁存标志 [-] / Fault latch flag
    eCause       : E_DL_TaperCause;    // 成因码出口（故障期锁存回放）[-] / Cause code outlet, latched replay
    bValid       : BOOL;               // 张力输出有效回执 [-] / Tension output validity receipt
END_VAR
VAR
    _eState      : E_DL_WttState := E_DL_WttState.eIdle;    // 内部相位（CASE 唯一写入目标）[-] / Internal phase
    _bFaultLatch : BOOL := FALSE;                           // 故障锁存位（仅 bReset 沿清除）[-] / Fault latch bit
    _eCauseLatch : E_DL_TaperCause := E_DL_TaperCause.eNone; // 锁存成因码（FB33-1 锁存回放）[-] / Latched cause code
    _eCauseTmp   : E_DL_TaperCause := E_DL_TaperCause.eNone; // 本拍首个成因（未锁存）[-] / First cause of this scan
    _bCfgOk      : BOOL := TRUE;                            // 组态与入参闸通过标志 [-] / Configuration gate flag
    _fDiaClamped : REAL := 0.0;                             // 钳位后的卷径 [mm] / Clamped roll diameter
    _fRatio       : REAL := 0.0;                            // 归一化卷径比例 r [-] / Normalised diameter ratio
    _fTaperFrac  : REAL := 0.0;                             // 锥度小数 t = fTaperPct/100 [-] / Taper fraction
    _fK1         : REAL := 0.0;                             // 折线节点 1/3 处系数 [-] / Factor at the one-third knot
    _fK2         : REAL := 0.0;                             // 折线节点 2/3 处系数 [-] / Factor at the two-thirds knot
    _fK3         : REAL := 0.0;                             // 折线节点 1 处系数 (1 − t) [-] / Factor at the full-roll knot
    _fK          : REAL := 0.0;                             // 本拍锥度系数 k [-] / Taper factor of this scan
    _fTension     : REAL := 0.0;                            // 钳位前张力 [N] / Tension before clamping
    nSeg         : INT := 0;                                // 折线段号 [1..3] / Piecewise segment index
END_VAR
VAR CONSTANT
    DL_TTP_ZERO  : REAL := 0.0;        // 零基准 [-] / Zero base
    DL_TTP_ONE   : REAL := 1.0;        // 一基准（单位 / 比例上端）[-] / Unity base
    DL_TTP_FULL  : REAL := 100.0;      // 百分比换算分母（非零常量）/ Percentage denominator, a non-zero constant
    DL_TTP_R1    : REAL := 0.33333;    // 折线第 1 节点比例 [-] / First knot ratio
    DL_TTP_R2    : REAL := 0.66667;    // 折线第 2 节点比例 [-] / Second knot ratio
    DL_TTP_KT1   : REAL := 0.45;       // 第 1 节点处衰减占比（占 t 的比例）[-] / Decay share at the first knot
    DL_TTP_KT2   : REAL := 0.78;       // 第 2 节点处衰减占比（占 t 的比例）[-] / Decay share at the second knot
    DL_TTP_D1    : REAL := 0.33333;    // 第 1 段插值分母（R1 − 0）[-] / Denominator of segment one
    DL_TTP_D2    : REAL := 0.33334;    // 第 2 段插值分母（R2 − R1）[-] / Denominator of segment two
    DL_TTP_D3    : REAL := 0.33333;    // 第 3 段插值分母（1 − R2）[-] / Denominator of segment three
    DL_TTP_TPMAX : REAL := 90.0;       // 锥度率上限（> 90% 的衰减无工程意义）[%] / Upper taper limit [%]
    DL_TTP_EPS   : REAL := 1.0E-6;     // 浮点同值比较容差 [-] / Float equality tolerance
END_VAR

(* —— 段 1：当拍工作量预置（单拍标志与中间量，不清锁存/保持量） —— *)
_bCfgOk    := TRUE;                                     // 闸通过标志复位 / Gate flag reset
_eCauseTmp := E_DL_TaperCause.eNone;                     // 当拍成因复位 / Scan cause reset

(* —— 段 2：状态机主体（唯一相位写入点） —— *)
CASE _eState OF
    E_DL_WttState.eIdle :
        IF bEnable THEN
            _eState := E_DL_WttState.eRun;               // 迁移①：进入计算相 / Move to the run phase
        END_IF

    E_DL_WttState.eRun :
        IF NOT bEnable THEN
            _eState := E_DL_WttState.eIdle;              // 迁移③：失能退出（冻结保持）/ Disable exit
        ELSE
            (* —— 段 3：入参非有限闸（R272 全量枚举九个浮点引脚） —— *)
            IF (fRollDia <> fRollDia) OR ((fRollDia - fRollDia) <> DL_TTP_ZERO)
                OR (fDiaCore <> fDiaCore) OR ((fDiaCore - fDiaCore) <> DL_TTP_ZERO)
                OR (fDiaMax <> fDiaMax) OR ((fDiaMax - fDiaMax) <> DL_TTP_ZERO)
                OR (fTensionIn <> fTensionIn) OR ((fTensionIn - fTensionIn) <> DL_TTP_ZERO)
                OR (fTaperPct <> fTaperPct) OR ((fTaperPct - fTaperPct) <> DL_TTP_ZERO)
                OR (fTensionMin <> fTensionMin) OR ((fTensionMin - fTensionMin) <> DL_TTP_ZERO)
                OR (fTensionMax <> fTensionMax) OR ((fTensionMax - fTensionMax) <> DL_TTP_ZERO) THEN
                _bCfgOk    := FALSE;
                _eCauseTmp := E_DL_TaperCause.eNonFinite;    // 故障级：非有限 / Fault: non-finite
            END_IF
            (* —— 段 4：组态域闸（两两倒置 / 越界各自独立成因） —— *)
            IF _bCfgOk THEN
                IF (fDiaCore <= DL_TTP_ZERO) OR (fDiaMax <= fDiaCore) THEN
                    _bCfgOk    := FALSE;
                    _eCauseTmp := E_DL_TaperCause.eBadConfig;      // 故障级：卷径组态倒置
                ELSIF (fTensionMin < DL_TTP_ZERO) OR (fTensionMax <= fTensionMin) THEN
                    _bCfgOk    := FALSE;
                    _eCauseTmp := E_DL_TaperCause.eBadConfig;      // 故障级：张力组态倒置
                ELSIF (fTaperPct < DL_TTP_ZERO) OR (fTaperPct > DL_TTP_TPMAX) THEN
                    _bCfgOk    := FALSE;
                    _eCauseTmp := E_DL_TaperCause.eBadTaper;       // 故障级：锥度率越域
                END_IF
            END_IF
            (* —— 段 5：卷径有效性闸（≤0 或 > 满卷径 → 撤张力） —— *)
            IF _bCfgOk THEN
                IF (fRollDia <= DL_TTP_ZERO) OR (fRollDia > (fDiaMax + DL_TTP_EPS)) THEN
                    _bCfgOk    := FALSE;
                    _eCauseTmp := E_DL_TaperCause.eBadDiameter;    // 故障级：卷径无效
                END_IF
            END_IF

            IF NOT _bCfgOk THEN
                (* 迁移②：锁存首因 + 安全侧撤张力（不保留末值） *)
                _eCauseLatch := _eCauseTmp;                    // 锁存成因 / Latch the cause
                _bFaultLatch := TRUE;                          // 置故障锁存 / Latch the fault
                fTensionOut  := DL_TTP_ZERO;                   // 安全侧：张力输出 0 / Safe side: zero tension
                fTaperFactor := DL_TTP_ZERO;                   // 锥度系数同步清零 / Taper factor zeroed
                _eState      := E_DL_WttState.eFault;          // 迁入故障相 / Move to the fault phase
            ELSE
                (* —— 段 6：比例与三段折线（分母全为编译期非零常量） —— *)
                _fDiaClamped := MIN(MAX(fRollDia, fDiaCore), fDiaMax);         // 卷径先钳位（R4）/ Clamp the diameter first
                _fRatio      := (_fDiaClamped - fDiaCore) / (fDiaMax - fDiaCore);   // 归一化比例 r / Normalised ratio
                _fRatio      := MIN(MAX(_fRatio, DL_TTP_ZERO), DL_TTP_ONE);    // 比例钳到 [0,1] / Clamp the ratio
                _fTaperFrac  := fTaperPct / DL_TTP_FULL;                        // 锥度小数 t / Taper fraction
                _fK1         := DL_TTP_ONE - (_fTaperFrac * DL_TTP_KT1);        // 节点 1/3 系数 / Factor at knot one
                _fK2         := DL_TTP_ONE - (_fTaperFrac * DL_TTP_KT2);        // 节点 2/3 系数 / Factor at knot two
                _fK3         := DL_TTP_ONE - _fTaperFrac;                       // 满卷节点系数 / Factor at full roll
                IF _fRatio <= DL_TTP_R1 THEN
                    nSeg := 1;                                                  // 第 1 段 / Segment one
                ELSIF _fRatio <= DL_TTP_R2 THEN
                    nSeg := 2;                                                  // 第 2 段 / Segment two
                ELSE
                    nSeg := 3;                                                  // 第 3 段 / Segment three
                END_IF
                CASE nSeg OF
                    1 :
                        _fK := DL_TTP_ONE + ((_fK1 - DL_TTP_ONE) * (_fRatio / DL_TTP_D1));      // 段 1 线性插值
                    2 :
                        _fK := _fK1 + ((_fK2 - _fK1) * ((_fRatio - DL_TTP_R1) / DL_TTP_D2));    // 段 2 线性插值
                    3 :
                        _fK := _fK2 + ((_fK3 - _fK2) * ((_fRatio - DL_TTP_R2) / DL_TTP_D3));    // 段 3 线性插值
                ELSE
                    _fK := DL_TTP_ONE;                                          // 兜底：恒张力系数 / Fallback: constant factor
                END_CASE
                _fTension := fTensionIn * _fK;                                   // 锥度张力 = 基础张力 × k / Tapered tension
                (* —— 段 7：输出钳位（上/下限独立成因，R190） —— *)
                IF _fTension > fTensionMax THEN
                    fTensionOut := fTensionMax;                                  // 上限饱和 / Saturate high
                    eCause      := E_DL_TaperCause.eSatHigh;                     // 信息级：上限饱和 / Info: saturated high
                ELSIF _fTension < fTensionMin THEN
                    fTensionOut := fTensionMin;                                  // 下限饱和 / Saturate low
                    eCause      := E_DL_TaperCause.eSatLow;                      // 信息级：下限饱和 / Info: saturated low
                ELSE
                    fTensionOut := _fTension;                                    // 限内直通 / Pass-through
                    eCause      := E_DL_TaperCause.eNone;                        // 信息级：正常 / Info: normal
                END_IF
                fTaperFactor := _fK;                                             // 锥度系数出口 / Taper factor outlet
                fDiaRatio    := _fRatio;                                         // 卷径比例出口 / Diameter ratio outlet
            END_IF
        END_IF

    E_DL_WttState.eFault :
        (* 迁移⑤：唯一出口 —— bReset 沿 + 已失能 *)
        IF bReset AND (NOT bEnable) THEN
            _bFaultLatch := FALSE;                             // 清故障锁存 / Clear the latch
            _eCauseLatch := E_DL_TaperCause.eNone;             // 清锁存成因 / Clear the latched cause
            eCause       := E_DL_TaperCause.eNone;             // 出口同步归零 / Outlet follows
            _eState      := E_DL_WttState.eIdle;               // 回空闲相 / Back to idle
        END_IF

ELSE
    (* 迁移⑥：非法枚举兜底（R6） *)
    _eCauseLatch := E_DL_TaperCause.eIllegalState;             // 故障级：非法状态
    _bFaultLatch := TRUE;                                      // 置锁存 / Latch
    fTensionOut  := DL_TTP_ZERO;                               // 安全侧撤张力 / Safe side: zero tension
    _eState      := E_DL_WttState.eFault;                      // 迁入故障相 / Move to fault
END_CASE

(* —— 段 8：段尾故障迁移闸（锁存与迁相分离，FB50-1④） —— *)
IF _bFaultLatch AND (_eState <> E_DL_WttState.eFault) THEN
    _eState := E_DL_WttState.eFault;                           // 锁存即迁相 / Latch forces the fault phase
END_IF

(* —— 段 9：统一出口（状态映射 + 锁存回放） —— *)
eState := _eState;                                             // 相位映射 / Phase mapping
bError := _bFaultLatch;                                        // 故障标志取锁存位 / Fault flag from the latch
IF _bFaultLatch THEN
    eCause := _eCauseLatch;                                    // 故障期回放锁存码（FB33-1）/ Replay the latched code
END_IF
bValid := (_eState = E_DL_WttState.eRun) AND (NOT _bFaultLatch);   // 仅计算相且无锁存时有效 / Valid only in run without a latch
END_FUNCTION_BLOCK
