(*
  FB_DL_CurtainEFEMZone  —  EFEM 区内光幕分区（四路遮光判向 / 屏蔽窗管理 / 顺序故障锁存）/ EFEM zone light-curtain muting
  分类 Category : DL_Device
  码位 Code     : 16#03_2_0C
  版本 Version  : 1.0.2
  来源 Source   : t1-5-tcopen — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : TwinCAT/TCopen 光幕屏蔽（muting）公开语义借鉴，clean-room 实现，未复制任何源码行
  功能 Function : 1) 四路光幕（进入侧 A / 进入侧 B / 区内 C / 出口侧 D）逐拍采集 bClear / bFault；
                  2) 遮光事件（上升沿）按先后入序列缓冲，A→B→C→D 判「正向通过」，D→C→B→A 判「反向通过」；
                  3) 序列至少两路且方向已定才允许开屏蔽窗（bMutingActive），屏蔽窗受 tMutingMax 强制限时；
                  4) 屏蔽期与非屏蔽期**都**输出受控速度限幅 fSpeedLimitOut（屏蔽 ≠ 无限速，规格强制项）；
                  5) 非顺序遮光（如 C 先于 A）或相邻遮光间隔超 tSequenceGap → bSequenceFault 锁存并禁屏蔽。
  边界 Boundary : ① 任一传感器自检失败（bFault = TRUE）**立即退出屏蔽**并置 023C（不得静默屏蔽，安全侧）；
                  ② tMutingMax 到点强制解屏蔽并置 022C（屏蔽超时是故障级，必须人工确认后复位）；
                  ③ 判向超 tSequenceGap 判「顺序失败」而非「无事件」：间隔超限说明通过节奏异常（可能是爬行/滞留），
                     按失败处理并清序列缓冲，码 012C（信息级）+ 021C（故障级，仅非顺序时）；
                     间隙计时随每次新遮光事件重启，间隔判据对每一对相邻事件均生效（R38 返修口径）；
                  ④ 解除式自证：bSequenceFault 解除 = bReset AND NOT bMutingEnable（组态退出屏蔽即可满足，R28-1）；
                     022C / 023C 同样由 rtReset.Q 清除，与本条互不掩盖（R188 双路径）；
                  ⑤ bZoneSafe 语义：区内光幕 C 通光，或屏蔽窗合法开启且无顺序故障与无传感器自检失败；
                     其余一律 FALSE（含 eAborted / eFault 相），上层据此做区域降速或停车；
                  ⑥ 时间参数 <= 0、速度限幅 <= 0、tSequenceGap > tMutingMax 均判组态错 020C（后者会让
                     屏蔽窗在序列判向前就超时，属不可能组态）。
  依赖 Depends  : I_DL_LightCurtain（DL_Device 既有契约，×4 注入，不实例化）；
                  仅 Standard.library（TON / R_TRIG / ABS / MIN / MAX）
  同拍双窗配比  : tSequenceGap（相邻遮光间隔）与 tMutingMax（屏蔽窗总时长）同源于通过节奏；
                  配比约束 tSequenceGap <= tMutingMax（组态闸强制），保证序列判据不会晚于屏蔽窗失效

  码表 Error codes（本件格 03_2_0C，子码步进 +0x10）:
    16#0003_020C 故障级：组态非法（时间参数 <= 0 / 速度限幅 <= 0 / tSequenceGap > tMutingMax）
    16#0003_021C 故障级：遮光顺序故障（非顺序遮光，锁存并禁屏蔽）
    16#0003_022C 故障级：屏蔽超时（tMutingMax 到点强制解屏蔽，锁存）
    16#0003_023C 故障级：光幕传感器自检失败（立即退出屏蔽，锁存）
    16#0003_024C 故障级：状态机落 ELSE 兜底（非法相位 ID）
    16#0003_010C 信息级：屏蔽窗开启（序列成立且方向已定，不置 bError）
    16#0003_011C 信息级：屏蔽窗正常结束（序列走完或全部通光，不置 bError）
    16#0003_012C 信息级：相邻遮光间隔超 tSequenceGap，序列缓冲已清（判向失败，不置 bError）

  修订历史 Revision :
    2026-11-18  v1.0.0  R37 首版
    2026-11-18  v1.0.2  R38 返修：间隙计时随新遮光事件重启（_bGapBreak 断输入请求，R188 自复位范式），间隔判据对每一对相邻事件均生效
  R38 已修复    : R37 终审挂账「间隙计时器不随新遮光事件重启」已修复（四路遮光上升沿统一汇合点置 _bGapBreak）
*)

TYPE E_DL_MutingState :
(
    eIdle     := 0,   // 空闲：未使能或屏蔽功能关闭 / Idle, muting disabled by the master enable or the configuration
    eEval     := 10,  // 评估：等待首个遮光事件 / Evaluating, waiting for the first occlusion
    eSeqCheck := 20,  // 判向：已有一路遮光，等第二路定方向 / Sequence check, waiting for the second occlusion
    eMuting   := 30,  // 屏蔽中：屏蔽窗开启并限时 / Muting, the window is open and time-limited
    eAborted  := 40,  // 中止：屏蔽被超时/自检失败中止，等待复位 / Aborted, waiting for a reset
    eFault    := 90   // 故障：顺序故障或组态故障锁定 / Fault, a latched sequence or configuration fault
);
END_TYPE

FUNCTION_BLOCK FB_DL_CurtainEFEMZone
VAR_INPUT
    bEnable       : BOOL := FALSE;             // 总使能，FALSE 时禁屏蔽并回空闲 / Master enable, low level forbids muting
    bReset        : BOOL := FALSE;             // 复位，上升沿清故障锁存 / Reset, rising edge clears the latch
    bMutingEnable : BOOL := FALSE;             // 屏蔽功能组态使能（退出即解除顺序故障）/ Muting feature enable
    fZoneSpeedLimit : REAL := 300.0;           // 区内速度限幅 [mm/s]，域 > 0 / Zone speed limit [mm/s]
    tMutingMax    : TIME := T#30S;             // 屏蔽最长时限 [ms]，域 > 0 / Maximum muting duration [ms]
    tSequenceGap  : TIME := T#5S;              // 相邻遮光间隔上限 [ms]，域 > 0 且 <= tMutingMax / Adjacent occlusion gap [ms]
    tClearHold    : TIME := T#500MS;           // 全通光确认驻留 [ms]，域 > 0 / All-clear confirm dwell [ms]
END_VAR
VAR_OUTPUT
    bZoneSafe      : BOOL;                     // 区域安全（区内无人或屏蔽合法）/ Zone safe
    bMutingActive  : BOOL;                     // 屏蔽进行中 / Muting active
    bSequenceFault : BOOL;                     // 遮光顺序故障锁存 / Occlusion sequence fault latched
    bMutingTimeout : BOOL;                     // 屏蔽超时锁存 / Muting timeout latched
    bSensorFault   : BOOL;                     // 任一光幕自检失败 / Any curtain self-test failure
    fSpeedLimitOut : REAL;                     // 生效速度限幅 [mm/s]（屏蔽期同样受控）/ Effective speed limit [mm/s]
    nSeqLength     : INT;                      // 当前序列长度 [路] / Present sequence length
    bValid         : BOOL;                     // 判据可用标志 / Criteria usable
    bError         : BOOL;                     // 故障标志，派生自锁存 / Fault flag derived from the latch
    nErrId         : UDINT;                    // 事件码，0 = 无事件 / Event code, 0 = no event
    eStateOut      : E_DL_MutingState;         // 状态出口，段尾单点映射 / State outlet, mapped at the tail
END_VAR
VAR_IN_OUT
    iCurtainA : I_DL_LightCurtain;             // 进入侧 A 光幕引用（注入，不实例化）/ Entry side A curtain reference
    iCurtainB : I_DL_LightCurtain;             // 进入侧 B 光幕引用（注入，不实例化）/ Entry side B curtain reference
    iCurtainC : I_DL_LightCurtain;             // 区内 C 光幕引用（注入，不实例化）/ In-zone C curtain reference
    iCurtainD : I_DL_LightCurtain;             // 出口侧 D 光幕引用（注入，不实例化）/ Exit side D curtain reference
END_VAR
VAR
    tonMuting   : TON;                         // 屏蔽最长时限计时，每拍无条件调用 / Muting duration timer, called unconditionally
    tonGap      : TON;                         // 相邻遮光间隔计时，每拍无条件调用 / Occlusion gap timer, called unconditionally
    tonClear    : TON;                         // 全通光确认驻留，每拍无条件调用 / All-clear dwell timer, called unconditionally
    tonHeart    : TON;                         // 周期心跳窗，自复位 / Periodic heartbeat window, self-resetting
    rtReset     : R_TRIG;                      // 复位上升沿 / Reset rising edge
    rtA         : R_TRIG;                      // A 路遮光上升沿 / Curtain A occlusion edge
    rtB         : R_TRIG;                      // B 路遮光上升沿 / Curtain B occlusion edge
    rtC         : R_TRIG;                      // C 路遮光上升沿 / Curtain C occlusion edge
    rtD         : R_TRIG;                      // D 路遮光上升沿 / Curtain D occlusion edge
    _eState     : E_DL_MutingState := E_DL_MutingState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _uFault     : UDINT;                       // 故障码锁存 / Latched fault code
    _uInfo      : UDINT;                       // 信息码，每拍重算 / Information code, recomputed per scan
    _bFault     : BOOL;                        // 故障锁存位 / Latched fault bit
    _bCfgBad    : BOOL;                        // 组态非法聚合 / Configuration invalid aggregate
    _bOccA      : BOOL;                        // A 路遮光 / Curtain A occluded
    _bOccB      : BOOL;                        // B 路遮光 / Curtain B occluded
    _bOccC      : BOOL;                        // C 路遮光 / Curtain C occluded
    _bOccD      : BOOL;                        // D 路遮光 / Curtain D occluded
    _bAnyOcc    : BOOL;                        // 任一路遮光 / Any curtain occluded
    _bAllClear  : BOOL;                        // 全部通光 / All curtains clear
    _bSensFault : BOOL;                        // 传感器自检失败聚合 / Sensor self-test failure aggregate
    _bSeqFault  : BOOL;                        // 顺序故障保持量 / Held sequence fault
    _bTimeout   : BOOL;                        // 屏蔽超时保持量 / Held muting timeout
    _bNewEvent  : BOOL;                        // 本拍有新的遮光事件 / A new occlusion event occurred
    _bGapBroken : BOOL;                        // 相邻间隔超限 / The gap limit was violated
    _bGapBreak  : BOOL := FALSE;               // 间隙计时断输入请求（新遮光事件沿触发，R188 自复位范式）/ Gap-timer break request, set by a new occlusion edge
    _nNewIdx    : INT;                         // 本拍新事件的序号（A=1..D=4）/ Order index of the new event
    _nDir       : INT;                         // 判向结果（0 未知 / +1 正向 / −1 反向）/ Direction verdict
    _anSeq      : ARRAY[0..3] OF INT;          // 序列缓冲（存序号 1..4）[路] / Sequence buffer holding indices one to four
    _nSeqLen    : INT;                         // 序列长度 [路] / Sequence length
    _nLastIdx   : INT;                         // 序列末项序号 / Index of the last accepted event
    _bHeartBrk  : BOOL := TRUE;                // 心跳窗断输入一拍 / One-scan heartbeat break
END_VAR
VAR CONSTANT
    DL_IDX_A      : INT := 1;          // A 路序号（进入侧）/ Order index of curtain A
    DL_IDX_B      : INT := 2;          // B 路序号（进入侧）/ Order index of curtain B
    DL_IDX_C      : INT := 3;          // C 路序号（区内）/ Order index of curtain C
    DL_IDX_D      : INT := 4;          // D 路序号（出口侧）/ Order index of curtain D
    DL_SEQ_NONE   : INT := 0;          // 序列空 / Empty sequence marker
    DL_SPEED_MIN  : REAL := 1.0;       // 速度限幅下限 [mm/s]（0 会让轴失去使能语义）/ Speed limit floor
    DL_SPEED_MAX  : REAL := 5000.0;    // 速度限幅上限 [mm/s] / Speed limit ceiling
    DL_HEART_WINDOW : TIME := T#2S;    // 心跳观察窗 [ms]，自复位节拍 / Heartbeat window, self-resetting
END_VAR

(* —— 段 0：定时器与边缘检测无条件周期刷新（R182：调用语句不得置于 IF / CASE 内） —— *)
rtReset(CLK := bReset);                                          // 复位上升沿，每拍必调
rtA(CLK := _bOccA);                                              // A 路遮光上升沿，每拍必调
rtB(CLK := _bOccB);                                              // B 路遮光上升沿，每拍必调
rtC(CLK := _bOccC);                                              // C 路遮光上升沿，每拍必调
rtD(CLK := _bOccD);                                              // D 路遮光上升沿，每拍必调
tonHeart(IN := (NOT tonHeart.Q) AND (NOT _bHeartBrk), PT := DL_HEART_WINDOW);  // 心跳窗自复位
_bHeartBrk := FALSE;                                             // 断输入拍在调用后自清
tonMuting(IN := (_eState = E_DL_MutingState.eMuting), PT := tMutingMax);        // 屏蔽限时（表达式入参）
tonGap(IN := ((_nSeqLen > 0) AND (_nSeqLen < 4)) AND (NOT _bGapBreak), PT := tSequenceGap);  // 相邻遮光间隔（表达式入参；断输入请求使 ET 随新事件归零重启）
_bGapBreak := FALSE;                                             // 断输入拍在调用后自清（新遮光沿在段 5 置位）
tonClear(IN := _bAllClear, PT := tClearHold);                                   // 全通光确认驻留（表达式入参）

(* —— 段 1：单拍量预清零（序列缓冲 / 保持量 / 锁存不入清单，R187①） —— *)
_uInfo      := 16#0000_0000;   // 信息码每拍重算
bError      := FALSE;          // 故障出口每拍重算，段 8 由锁存派生
bValid      := FALSE;          // 可用标志缺省 FALSE
bMutingActive := FALSE;        // 屏蔽出口缺省 FALSE，段 8 单点置位
bZoneSafe   := FALSE;          // 区域安全缺省 FALSE（安全侧缺省）
_bCfgBad    := FALSE;          // 组态非法预清零
_bNewEvent  := FALSE;          // 新事件标志预清零
_bGapBroken := FALSE;          // 间隔超限标志预清零
_nNewIdx    := DL_SEQ_NONE;    // 新事件序号预清零

(* —— 段 2：复位沿清锁存 + 按码专清（R188 双路径，互不掩盖） —— *)
IF rtReset.Q THEN
    IF NOT bMutingEnable THEN
        _bSeqFault := FALSE;           // 解除式：bReset AND NOT bMutingEnable（组态退出屏蔽即可满足）
    END_IF
    IF NOT _bSeqFault THEN
        _bFault   := FALSE;            // 顺序故障保持量已释放才清故障位（防「码清位不清」）
        _uFault   := 16#0000_0000;     // 清锁存码
        _bTimeout := FALSE;            // 屏蔽超时保持量清零（与 022C 同源）
        _nSeqLen  := 0;                // 序列缓冲长度归零
        _nDir     := 0;                // 判向结果归零
    END_IF
END_IF
IF (_uFault = 16#0003_021C) AND (NOT _bSeqFault) THEN
    _uFault := 16#0000_0000;           // 按码专清：顺序故障保持量已释放 → 对应码清除
    _bFault := FALSE;                  // 锁存位同步清
END_IF
IF (_uFault = 16#0003_022C) AND (NOT _bTimeout) THEN
    _uFault := 16#0000_0000;           // 按码专清：屏蔽超时保持量已释放 → 对应码清除
    _bFault := FALSE;                  // 锁存位同步清
END_IF

(* —— 段 3：组态域闸（覆盖全部参与判据换算的引脚，R151） —— *)
IF (fZoneSpeedLimit <> fZoneSpeedLimit) OR (fZoneSpeedLimit < DL_SPEED_MIN) THEN
    _bCfgBad := TRUE;              // 速度限幅非法（下限防 0 值让上层误判为无限速）
END_IF
IF fZoneSpeedLimit > DL_SPEED_MAX THEN
    _bCfgBad := TRUE;              // 速度限幅超上界（组态量纲错）
END_IF
IF TIME_TO_DINT(tMutingMax) <= 0 THEN
    _bCfgBad := TRUE;              // 屏蔽限时非法
END_IF
IF TIME_TO_DINT(tSequenceGap) <= 0 THEN
    _bCfgBad := TRUE;              // 判向间隔非法
END_IF
IF TIME_TO_DINT(tClearHold) <= 0 THEN
    _bCfgBad := TRUE;              // 全通光确认驻留非法
END_IF
IF (TIME_TO_DINT(tSequenceGap) > 0) AND (TIME_TO_DINT(tMutingMax) > 0) AND
   (TIME_TO_DINT(tSequenceGap) > TIME_TO_DINT(tMutingMax)) THEN
    _bCfgBad := TRUE;              // 判向间隔大于屏蔽限时：序列判据必然晚于屏蔽窗失效（不可能组态）
END_IF
IF _bCfgBad THEN
    _uFault := 16#0003_020C;       // 故障级：组态非法
    _bFault := TRUE;               // 锁存位置位（复位沿可清）
    bError  := TRUE;               // 故障标志置位（R45 配对）
    _eState := E_DL_MutingState.eFault;  // 进故障相
END_IF

(* —— 段 4：四路光幕采集（只读属性，零命令下发） —— *)
_bOccA := NOT iCurtainA.bClear;    // A 路遮光（通光取反）
_bOccB := NOT iCurtainB.bClear;    // B 路遮光
_bOccC := NOT iCurtainC.bClear;    // C 路遮光（区内）
_bOccD := NOT iCurtainD.bClear;    // D 路遮光
_bAnyOcc := _bOccA OR _bOccB OR _bOccC OR _bOccD;                    // 任一路遮光
_bAllClear := (NOT _bAnyOcc);                                       // 全部通光
_bSensFault := iCurtainA.bFault OR iCurtainB.bFault OR
               iCurtainC.bFault OR iCurtainD.bFault;                // 任一路自检失败
bSensorFault := _bSensFault;                                        // 自检失败出口（安全镜像）

(* —— 段 4A：自检失败立即退出屏蔽（安全侧，先于一切序列判定，R190 归因唯一） —— *)
IF _bSensFault THEN
    IF (_eState = E_DL_MutingState.eMuting) OR (_eState = E_DL_MutingState.eSeqCheck) THEN
        _uFault := 16#0003_023C;   // 故障级：光幕传感器自检失败，屏蔽立即退出
        _bFault := TRUE;           // 锁存
        bError  := TRUE;           // 故障标志置位（R45 配对）
        _eState := E_DL_MutingState.eAborted;  // 中止相（等复位）
        _nSeqLen := 0;             // 序列缓冲清空（自检失败后旧序列不可信）
        _nDir := 0;                // 判向清空
    END_IF
END_IF

(* —— 段 5：遮光事件排序（序号入缓冲，方向唯一确定后才允许屏蔽） —— *)
IF _bAnyOcc AND (NOT _bSensFault) THEN
    IF rtA.Q THEN
        _bNewEvent := TRUE; _nNewIdx := DL_IDX_A;   // A 路新事件
    ELSIF rtB.Q THEN
        _bNewEvent := TRUE; _nNewIdx := DL_IDX_B;   // B 路新事件
    ELSIF rtC.Q THEN
        _bNewEvent := TRUE; _nNewIdx := DL_IDX_C;   // C 路新事件
    ELSIF rtD.Q THEN
        _bNewEvent := TRUE; _nNewIdx := DL_IDX_D;   // D 路新事件
    END_IF
END_IF

IF _bNewEvent THEN
    _bGapBreak := TRUE;                             // R38 返修：新遮光上升沿（A/B/C/D 四路统一汇合点）置断输入请求，
                                                    // 下一拍 tonGap IN 断开（Q 天然为 FALSE）→ ET 归零，间隙从新事件重新计时；
                                                    // 本拍 _bGapBreak 置位不影响本拍已完成的 tonGap 调用（段 0 先行）
    IF tonGap.Q AND (_nSeqLen > 0) THEN
        _bGapBroken := TRUE;                        // 相邻遮光间隔超限：判向失败（不是「无事件」）
        _nSeqLen := 0;                              // 序列缓冲清空
        _nDir := 0;                                 // 方向作废
        _uInfo := 16#0003_012C;                     // 信息级：间隔超限，序列已清
    END_IF
    IF _nSeqLen = 0 THEN
        _anSeq[0] := _nNewIdx;                      // 首路遮光入缓冲
        _nSeqLen := 1;                              // 长度 1
        _nLastIdx := _nNewIdx;                      // 末项记录
        _nDir := 0;                                 // 方向待定
    ELSIF _nSeqLen < 4 THEN
        IF _nDir = 0 THEN
            IF _nNewIdx = (_nLastIdx + 1) THEN
                _nDir := 1;                         // 序号递增：正向通过
            ELSIF _nNewIdx = (_nLastIdx - 1) THEN
                _nDir := -1;                        // 序号递减：反向通过
            ELSE
                _bSeqFault := TRUE;                 // 非相邻：非顺序遮光（如 C 先于 A）
            END_IF
        ELSE
            IF _nNewIdx <> (_nLastIdx + _nDir) THEN
                _bSeqFault := TRUE;                 // 与已定方向不符：非顺序遮光
            END_IF
        END_IF
        IF _bSeqFault THEN
            _uFault := 16#0003_021C;                // 故障级：遮光顺序故障（禁屏蔽）
            _bFault := TRUE;                        // 锁存
            bError  := TRUE;                        // 故障标志置位（R45 配对）
            _eState := E_DL_MutingState.eFault;     // 进故障相
        ELSE
            _anSeq[_nSeqLen] := _nNewIdx;           // 顺序成立：事件入缓冲
            _nSeqLen := _nSeqLen + 1;               // 长度递增（上限 4 由外条件守）
            _nLastIdx := _nNewIdx;                  // 末项更新
        END_IF
    END_IF
END_IF
nSeqLength := _nSeqLen;                             // 序列长度出口（诊断用）

(* —— 段 6：相位机（只做迁移；屏蔽出口在段 8） —— *)
CASE _eState OF

E_DL_MutingState.eIdle:
    IF bEnable AND bMutingEnable AND (NOT _bFault) AND (NOT _bCfgBad) THEN
        _eState := E_DL_MutingState.eEval;          // 使能且屏蔽功能开：进评估相
    END_IF

E_DL_MutingState.eEval:
    IF (NOT bEnable) OR (NOT bMutingEnable) THEN
        _eState := E_DL_MutingState.eIdle;          // 退出屏蔽功能：回空闲
    ELSIF _nSeqLen >= 1 THEN
        _eState := E_DL_MutingState.eSeqCheck;      // 已有首路遮光：进判向相
    END_IF

E_DL_MutingState.eSeqCheck:
    IF (NOT bEnable) OR (NOT bMutingEnable) THEN
        _eState := E_DL_MutingState.eIdle;          // 退出屏蔽功能
        _nSeqLen := 0;                              // 序列清空
        _nDir := 0;                                 // 方向清空
    ELSIF (_nSeqLen >= 2) AND (_nDir <> 0) THEN
        _eState := E_DL_MutingState.eMuting;        // 方向已定：开屏蔽窗
        _uInfo  := 16#0003_010C;                    // 信息级：屏蔽窗开启
    ELSIF tonGap.Q THEN
        _uInfo := 16#0003_012C;                     // 信息级：判向超时（不足两路）
        _nSeqLen := 0;                              // 序列清空，等下一轮
        _nDir := 0;
        _eState := E_DL_MutingState.eEval;          // 回评估相
    END_IF

E_DL_MutingState.eMuting:
    IF _bSensFault THEN
        _eState := E_DL_MutingState.eAborted;       // 自检失败：立即退出（段 4A 已置码）
    ELSIF (NOT bEnable) OR (NOT bMutingEnable) THEN
        _eState := E_DL_MutingState.eEval;          // 组态退出屏蔽：解屏蔽
        _nSeqLen := 0;
        _nDir := 0;
    ELSIF tonMuting.Q THEN
        _bTimeout := TRUE;                          // 屏蔽超时保持量
        _uFault := 16#0003_022C;                    // 故障级：屏蔽超时强制解屏蔽
        _bFault := TRUE;                            // 锁存
        bError  := TRUE;                            // 故障标志置位（R45 配对）
        _eState := E_DL_MutingState.eAborted;       // 中止相
        _nSeqLen := 0;
        _nDir := 0;
    ELSIF tonClear.Q THEN
        _uInfo := 16#0003_011C;                     // 信息级：全部通光并驻留完成，屏蔽窗正常结束
        _nSeqLen := 0;                              // 序列清空，准备下一件
        _nDir := 0;
        _eState := E_DL_MutingState.eEval;          // 回评估相
    END_IF

E_DL_MutingState.eAborted:
    IF (NOT bEnable) THEN
        _eState := E_DL_MutingState.eIdle;          // 失能：回空闲
    ELSIF (NOT _bFault) AND bMutingEnable AND (NOT _bSensFault) THEN
        _eState := E_DL_MutingState.eEval;          // 复位完成且自检恢复：回评估相
    END_IF

E_DL_MutingState.eFault:
    IF (NOT _bFault) AND (NOT _bCfgBad) AND bEnable AND bMutingEnable THEN
        _eState := E_DL_MutingState.eEval;          // 锁存已清且组态合法：回评估相
    END_IF

ELSE
    _uFault := 16#0003_024C;                        // 故障级：相位 ID 越界（枚举兜底）
    _bFault := TRUE;                                // 锁存
    bError  := TRUE;                                // 故障标志置位（R45 配对）
    _eState := E_DL_MutingState.eFault;             // 强制回故障相
END_CASE

(* —— 段 7：故障码优先级链（每个 bError 置位源在此均有码，R45 配对） —— *)
IF _bCfgBad THEN
    bError := TRUE;                                 // 组态非法：码已在段 3 置位（020C）
END_IF

(* —— 段 8：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
bMutingActive   := (_eState = E_DL_MutingState.eMuting) AND (NOT _bFault);  // 屏蔽出口：仅在屏蔽相且无故障
bSequenceFault  := _bSeqFault;                                              // 顺序故障出口（保持量）
bMutingTimeout  := _bTimeout;                                               // 屏蔽超时出口（保持量）
fSpeedLimitOut  := fZoneSpeedLimit;                                         // 生效限幅：屏蔽期同样受控（屏蔽 ≠ 无限速）
bZoneSafe       := ((NOT _bOccC) AND (NOT _bSensFault) AND (NOT _bFault)) OR
                   (bMutingActive AND (NOT _bSeqFault) AND (NOT _bSensFault));  // 区域安全：区内通光或屏蔽合法
eStateOut       := _eState;                                                 // 状态出口
IF _bFault THEN
    nErrId := _uFault;                           // 故障锁存码回放（不在故障相按当下输入重推）
    bError := TRUE;                              // 故障出口派生自锁存
ELSE
    nErrId := _uInfo;                            // 信息码
END_IF
bValid := bEnable AND bMutingEnable AND (NOT _bFault) AND (NOT _bCfgBad);  // 判据可用

END_FUNCTION_BLOCK
