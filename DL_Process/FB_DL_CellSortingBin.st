(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CellSortingBin
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 电池片分选落料 + 料仓满溢调度。
 *                           ① 档位→料仓映射：anGradeMap[nGrade − 1] 给出目标仓号，−1 表示该档
 *                              "不落料"（工艺上存在 NG 档直接走废料带、不进分选仓的情形）。
 *                           ② 满溢调度：目标仓已满（anBinCount ≥ anBinCapacity）时**不丢片**，
 *                              自动旁路到备仓 nBackupBin，并置 bOverflowBypass 锁存告警
 *                              （旁路是被动降级，必须让维护看见；悄悄丢片是最坏结果）。
 *                           ③ 双满兜底：目标仓与备仓同时满 → bNoBin 锁存故障、不落料、
 *                              由上层停机或切换收料框（本件不擅自选第三个仓——仓序属产线配置，
 *                              不是算法可以推断的）。
 *                           ④ 计数在**成功落料后**自增（inc-place 写回调用方的 anBinCount），
 *                              杜绝"先计数后落料"导致的仓位数虚高。
 * 接口     (Interface)  : 输入 nGrade 当前档位（1..8）、bDropCmd 落料命令（上升沿执行）、
 *                         anBinCount 各仓当前计数（VAR_IN_OUT，成功落料后自增）、
 *                         anBinCapacity 各仓容量（配置）、anGradeMap 档位到料仓映射（配置，−1 不落）、
 *                         nBackupBin 备仓号、bReset 复位；输出 nTargetBin 目标仓（−1 无）、
 *                         bDrop 落料脉冲（单拍）、bOverflowBypass 旁路告警（锁存）、
 *                         bNoBin 无可用仓（锁存）、bGradeUnmapped 该档不落料（当拍量）、
 *                         eState / eCause / bError。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做"档位到仓号的选择与满溢旁路"，
 *                         不驱动气缸/翻转机构、不做到位确认**。执行机构动作与到位联锁属
 *                         落料执行 POU（可复用 `I_DL_Cylinder` 族）；本件只出目标仓号与落料脉冲。
 *                         ② 组态闸：nGrade < 1 或 > 8（越映射表边界）、nBackupBin 越 0..3、
 *                         任一 anBinCapacity[i] <= 0、映射表值 > 3（越仓边界）或 < −1、
 *                         映射表指向的仓不存在 → 故障锁存，落料脉冲不出（宁可不落，不可乱落）。
 *                         ③ 4 仓定长（ARRAY[0..3]）、8 档定长（ARRAY[0..7]）：容量写死在类型里，
 *                         改仓数须改类型定义，不允许"运行期可变长度"（那会越界）。
 *                         ④ 单枚 R_TRIG（bDropCmd）+ 单枚 R_TRIG（bReset）段 0 无条件周期刷新；
 *                         无 TON，故无跨相复位风险。
 *                         ⑤ 故障相与旁路锁存迁出唯一路径 = bReset 上升沿（R228B）。
 *                         ⑥ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_Cylinder` 族（执行机构）分工——本件是**调度/记账**件，
 *                         输出仓号与脉冲；执行件负责把片真送进仓。二者不可混写在一个 FB 里，
 *                         否则换执行机构时要重测记账逻辑。
 * 来源标签 (Source Tag) : ROADMAP B 类（光伏电池片分选落料，自研 clean-room，无外源代码）
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 → 清 bNoBin / bOverflowBypass 锁存。
 *                         自证可满足：清仓（计数减少）或复位后即解除，无恒假因子。
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 INT 仓号 + BOOL 组 + ENUM
 *                         （eState / eCause）；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 数组边界闸 + 映射值域闸 + 容量非正闸 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE ｜ R7 ✓ R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R46 首版（批次 3 · 序号 14）
 *==============================================================================*)

TYPE E_DL_CsbState :
(
    eIdle  := 0,    // 等待落料命令 / Awaiting a drop command
    eRun   := 10,   // 正常落料运行相 / Normal dropping
    eBypass:= 20,   // 满溢旁路相（走备仓，告警保持） / Overflow bypass phase
    eFault := 90    // 无可用仓/组态故障相 / No-bin or configuration fault
);
END_TYPE

TYPE E_DL_CsbCause :
(
    eNone        := 0,   // 无异常 / No anomaly
    eCfgIllegal  := 1,   // 组态非法（映射/容量/备仓越界） / Illegal configuration
    eOverflow    := 2,   // 目标仓满溢，已旁路到备仓 / Target bin full, bypassed to the backup bin
    eNoBin       := 3,   // 目标仓与备仓同时满，无可用仓 / Target and backup both full
    eGradeUnmapped:= 4,  // 该档不落料（映射为 −1） / Grade intentionally not dropped
    ePhaseBad    := 5    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_CellSortingBin
VAR_IN_OUT
    anBinCount : ARRAY[0..3] OF DINT;       // 各仓当前计数（成功落料后本件自增） [片] / Bin counts, incremented by this unit on success [pcs]
END_VAR
VAR_INPUT
    nGrade        : INT := 1;               // 当前档位，域 1..8 / Present grade, 1..8
    bDropCmd      : BOOL := FALSE;          // 落料命令，上升沿执行一次 [-] / Drop command, acts once per rising edge
    anBinCapacity : ARRAY[0..3] OF DINT;    // 各仓容量（配置），每项域 > 0 [片] / Bin capacities, each > 0 [pcs]
    anGradeMap    : ARRAY[0..7] OF INT;     // 档位到仓映射（配置），值域 −1 或 0..3 [-] / Grade-to-bin map, -1 or 0..3
    nBackupBin    : INT := 3;               // 备仓号，域 0..3 / Backup bin index, 0..3
    bReset        : BOOL := FALSE;          // 复位，上升沿清旁路与无仓锁存 [-] / Reset, rising edge clears latches
END_VAR
VAR_OUTPUT
    nTargetBin      : INT;                  // 本拍目标仓号，−1 表示无 / Target bin this scan, -1 means none
    bDrop           : BOOL;                 // 落料脉冲（单拍） [-] / Drop pulse, single scan
    bOverflowBypass : BOOL;                 // 满溢旁路告警（锁存） [-] / Overflow bypass alarm, latched
    bNoBin          : BOOL;                 // 无可用仓（锁存故障） [-] / No available bin, latched fault
    bGradeUnmapped  : BOOL;                 // 该档不落料（当拍量，非故障） [-] / Grade not dropped, per scan, not a fault
    eState          : E_DL_CsbState;        // 状态出口 [-] / State outlet
    eCause          : E_DL_CsbCause;        // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError          : BOOL;                 // 故障标志（无仓/组态非法；旁路不算故障） [-] / Error flag, bypass is not a fault
END_VAR
VAR
    _eState   : E_DL_CsbState := E_DL_CsbState.eIdle;    // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause   : E_DL_CsbCause := E_DL_CsbCause.eNone;    // 成因锁存量 / Latched cause
    rtDrop    : R_TRIG;                 // 落料命令沿实例，段 0 无条件调用 / Drop edge instance
    rtReset   : R_TRIG;                 // 复位沿实例，段 0 无条件调用 / Reset edge instance
    _bBypass  : BOOL;                   // 旁路告警锁存位（锁存量） / Latched bypass alarm
    _bNoBin   : BOOL;                   // 无可用仓锁存位（锁存量） / Latched no-bin fault
    _bCfgBad  : BOOL;                   // 组态非法当拍量 [-] / Illegal configuration this scan
    _bMapBad  : BOOL;                   // 映射表非法当拍量 [-] / Illegal map this scan
    _nBin     : INT;                    // 映射得到的目标仓号中间量 [-] / Mapped target bin intermediate
    _nMapIdx  : INT;                    // 映射查表索引（已钳位） [-] / Clamped map index
    _i        : INT;                    // 遍历索引 / Loop index
END_VAR
VAR CONSTANT
    DL_CSB_BINMAX : INT := 3;           // 仓号上界（与 ARRAY[0..3] 一致） [仓] / Bin index bound matching the array
    DL_CSB_GRDMAX : INT := 8;           // 档位上界（与 ARRAY[0..7] 一致） [档] / Grade bound matching the array
    DL_CSB_NOBIN  : INT := -1;          // 无目标仓哨兵值 [-] / Sentinel for "no target bin"
END_VAR

(* —— 段 0：组态闸派生 + 两沿实例无条件周期刷新 —— *)
_bMapBad := FALSE;                                          // 映射非法初值 / Map-illegal initial value
FOR _i := 0 TO DL_CSB_GRDMAX - 1 DO
    IF (anGradeMap[_i] > DL_CSB_BINMAX) OR (anGradeMap[_i] < DL_CSB_NOBIN) THEN
        _bMapBad := TRUE;                                   // 映射值越界（> 3 或 < −1） / Map value out of range
    END_IF
END_FOR
FOR _i := 0 TO DL_CSB_BINMAX DO
    IF anBinCapacity[_i] <= 0 THEN
        _bMapBad := TRUE;                                   // 容量非正（永不装满或立即装满，皆病态） / Non-positive capacity is degenerate
    END_IF
END_FOR
_bCfgBad := _bMapBad
        OR (nBackupBin < 0) OR (nBackupBin > DL_CSB_BINMAX)   // 备仓号越界 / Backup index out of range
        OR (nGrade < 1) OR (nGrade > DL_CSB_GRDMAX);          // 档位越映射表边界 / Grade out of the map bounds
rtDrop(CLK := bDropCmd);                                    // 落料沿，每拍必调（R228A） / Drop edge, every scan
rtReset(CLK := bReset);                                     // 复位沿，每拍必调 / Reset edge, every scan

(* —— 段 1：单拍量预清零（锁存量 _bBypass / _bNoBin / _eCause 不入清单，R107） —— *)
nTargetBin     := DL_CSB_NOBIN;     // 目标仓缺省无 / Target bin defaults to none
bDrop          := FALSE;            // 落料脉冲每拍预清 / Drop pulse preset
bOverflowBypass:= FALSE;            // 旁路出口每拍预清 / Bypass outlet preset
bNoBin         := FALSE;            // 无仓出口每拍预清 / No-bin outlet preset
bGradeUnmapped := FALSE;            // 不落料标志每拍预清 / Unmapped flag preset
bError         := FALSE;            // 故障标志每拍预清（R45 配对） / Error flag preset

(* —— 段 2：复位沿 + 组态闸 —— *)
IF rtReset.Q THEN
    _bBypass := FALSE;                                  // 清旁路告警锁存 / Clear the bypass alarm
    _bNoBin  := FALSE;                                  // 清无仓锁存 / Clear the no-bin latch
    _eCause  := E_DL_CsbCause.eNone;                    // 清成因 / Clear cause
    IF _eState = E_DL_CsbState.eFault THEN
        _eState := E_DL_CsbState.eIdle;                 // 故障相迁出（R228B） / Leave fault phase
    END_IF
    IF _eState = E_DL_CsbState.eBypass THEN
        _eState := E_DL_CsbState.eRun;                  // 旁路相迁出（第二条可迁出路径） / Leave bypass phase, second exit path
    END_IF
END_IF
IF _bCfgBad THEN
    _eState := E_DL_CsbState.eFault;                    // 入故障相 / Enter fault phase
    _eCause := E_DL_CsbCause.eCfgIllegal;               // 归因：组态非法 / Cause: illegal configuration
END_IF

(* —— 段 3：落料调度（命令沿 + 组态合法；单点写入锁存与计数） —— *)
IF rtDrop.Q AND (NOT _bCfgBad) THEN
    _nMapIdx := nGrade - 1;                             // 映射查表索引（段 0 已闸 1..8） / Map index, grade bounds already gated
    IF _nMapIdx < 0 THEN
        _nMapIdx := 0;                                  // 下界钳（双保险） / Lower clamp, second guard
    END_IF
    IF _nMapIdx > DL_CSB_GRDMAX - 1 THEN
        _nMapIdx := DL_CSB_GRDMAX - 1;                  // 上界钳（双保险） / Upper clamp, second guard
    END_IF
    _nBin := anGradeMap[_nMapIdx];                      // 目标仓号 / Mapped target bin
    IF _nBin = DL_CSB_NOBIN THEN
        bGradeUnmapped := TRUE;                         // 该档不落料（工艺意图，非故障） / Grade intentionally not dropped
        _eCause := E_DL_CsbCause.eGradeUnmapped;        // 成因：映射为不落料 / Cause: mapped to no-drop
    ELSE
        IF anBinCount[_nBin] < anBinCapacity[_nBin] THEN
            nTargetBin := _nBin;                        // 目标仓有余量，正常落 / Target bin has room
            anBinCount[_nBin] := anBinCount[_nBin] + 1; // 成功落料后计数（先判满后自增） / Increment only after a successful drop
            bDrop := TRUE;                              // 落料脉冲 / Drop pulse
            IF _eState = E_DL_CsbState.eIdle THEN
                _eState := E_DL_CsbState.eRun;          // 首次落料入运行相 / First drop enters run
            END_IF
        ELSIF anBinCount[nBackupBin] < anBinCapacity[nBackupBin] THEN
            nTargetBin := nBackupBin;                   // 旁路到备仓 / Bypass to the backup bin
            anBinCount[nBackupBin] := anBinCount[nBackupBin] + 1;   // 备仓计数自增 / Increment the backup bin
            bDrop := TRUE;                              // 落料脉冲 / Drop pulse
            _bBypass := TRUE;                           // 旁路告警锁存（被动降级必须可见） / Latch the bypass alarm
            _eCause := E_DL_CsbCause.eOverflow;         // 成因：满溢旁路 / Cause: overflow bypass
            _eState := E_DL_CsbState.eBypass;           // 入旁路相 / Enter the bypass phase
        ELSE
            nTargetBin := DL_CSB_NOBIN;                 // 双满：无可用仓 / Both full: no available bin
            _bNoBin := TRUE;                            // 无仓锁存故障 / Latch the no-bin fault
            _eCause := E_DL_CsbCause.eNoBin;            // 成因：无可用仓 / Cause: no available bin
            _eState := E_DL_CsbState.eFault;            // 入故障相 / Enter the fault phase
        END_IF
    END_IF
END_IF

(* —— 段 4：锁存相位迁移闸（无仓故障必须停在故障相，旁路必须停在旁路相） —— *)
IF _bNoBin AND (_eState <> E_DL_CsbState.eFault) THEN
    _eState := E_DL_CsbState.eFault;                    // 无仓锁存即入故障相 / No-bin latch enters fault
END_IF

(* —— 段 5：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_CsbState.eIdle:
    IF _bCfgBad THEN                                    // 出口 1：组态非法 / Illegal configuration
        _eState := E_DL_CsbState.eFault;
    ELSIF rtDrop.Q AND (NOT _bCfgBad) THEN              // 出口 2：已有落料动作 / A drop has been dispatched
        _eState := E_DL_CsbState.eRun;
    END_IF

E_DL_CsbState.eRun:
    IF _bCfgBad OR _bNoBin THEN                         // 出口 1：故障（组态或无仓） / Fault, config or no-bin
        _eState := E_DL_CsbState.eFault;
    ELSIF _bBypass THEN                                 // 出口 2：发生过满溢旁路 / An overflow bypass occurred
        _eState := E_DL_CsbState.eBypass;
    END_IF

E_DL_CsbState.eBypass:
    IF _bNoBin THEN                                     // 出口 1：旁路后仍双满 / Both full even after bypass
        _eState := E_DL_CsbState.eFault;
    ELSIF _bBypass = FALSE THEN                         // 出口 2：旁路告警被复位清除 / Bypass alarm cleared by reset
        _eState := E_DL_CsbState.eRun;
    END_IF

E_DL_CsbState.eFault:
    ;                                                   // 故障相：仅段 2 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _eCause := E_DL_CsbCause.ePhaseBad;                 // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_CsbState.eFault;                    // 强拉故障相 / Force the fault phase
    bError  := TRUE;                                    // 故障标志 / Error flag

END_CASE

(* —— 段 6：出口单点映射（名实双出口，R191；旁路是告警不是故障，此处写死分级） —— *)
bOverflowBypass := _bBypass;                            // 旁路告警与锁存同源 / Bypass alarm from latch
bNoBin          := _bNoBin;                             // 无仓与锁存同源 / No-bin from latch
bError          := _bNoBin OR _bCfgBad;                 // 故障标志：无仓或组态非法（旁路不计入故障级） / Error: no-bin or illegal config, bypass excluded
eState          := _eState;                             // 状态出口 / State outlet
eCause          := _eCause;                             // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
