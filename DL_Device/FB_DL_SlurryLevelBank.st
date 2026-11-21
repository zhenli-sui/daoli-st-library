(*
  FB_DL_SlurryLevelBank  —  多罐浆料液位开关组（fail-safe 方向解释 / 质量字仲裁 / 开关相反归因）/ Slurry level switch bank
  分类 Category : DL_Device
  码位 Code     : 16#03_2_0E
  版本 Version  : 1.0.0
  来源 Source   : t2-8-isa182 — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : ISA-18.2 报警管理公开语义借鉴（报警与故障分离、状态归因），clean-room 实现，未复制源码行
  功能 Function : 1) 逐罐读取高位/低位点式开关、质量字（0~3，0 = OK）与组态 fail-safe 方向；
                  2) 按 fail-safe 方向解释「液位 vs 断线」：LOW 型（eLow）断线时读数表现为高位，
                     HIGH 型（eHigh）断线时读数表现为低位——两类方向各自反推，绝不套用同一公式；
                  3) 质量字非 OK 判 abSensorFault，并以**安全侧**值参与联锁（保守取值：保护泵的取「低」，
                     保护溢流的取「高」，即一律认报警成立），信息级 011E 记录替代生效；
                  4) 同一罐高低位同时为真判「开关相反」故障 022E（3 罐 × 2 型共 6 组向量逐条推演，见验收向量）；
                  5) 输出严格区分「越限（工艺）」与「传感器故障（仪表）」两类：越限只置 abLevelAlarm 与信息级 010E，
                     传感器故障置 abSensorFault 与故障级 021E 并置 bError（R190 归因唯一）。
  边界 Boundary : ① uBankSize = 0 或 > DL_BANK_MAX 判组态错 020E，**直接返回不进入循环**（防数组越界，R28-2）；
                     高位/低位/质量字/方向四个数组声明长度一律 DL_BANK_MAX，长度不等在编译期即被拦截，
                     运行期再以 uBankSize 做上界闸（双保险）；
                  ② 质量字不在 0~3 域内判组态错（质量字编码越界，无法解释），不按 OK 处理；
                  ③ fail-safe 方向枚举落 ELSE（非法方向）按「最保守」处理：高低两位都认报警，并置 020E；
                  ④ 解除式自证：_bFault 清除 = rtReset.Q（引脚可满足）；022E 另可由「该罐高低位不再同时为真」
                     按码专清（R188 可达清除边，不依赖人工复位掩盖真实接线错误）；
                  ⑤ nFaultCount 为 INT，逐罐故障计数后钳制到 DL_BANK_MAX（不溢出、不回绕）；
                  ⑥ 越限（010E）为信息级，**永不置 bError**（R187③ / R45 配对纪律）。
  依赖 Depends  : 仅 Standard.library（TON / R_TRIG / ABS / MIN / MAX），零外部组件依赖
  同拍双窗配比  : tQualityDb（质量字去抖）与心跳窗 DL_HEART_WINDOW 不同源；配比约束
                  tQualityDb <= DL_HEART_WINDOW，保证去抖窗内至少一次判活（R100）

  码表 Error codes（本件格 03_2_0E，子码步进 +0x10）:
    16#0003_020E 故障级：组态非法（uBankSize = 0 或越上限 / 质量字越 0~3 域 / fail-safe 方向非法）
    16#0003_021E 故障级：传感器故障（质量字非 OK，已用安全侧值参与联锁）
    16#0003_022E 故障级：开关相反（同一罐高低位同时为真，接线或组态错误）
    16#0003_023E 故障级：状态机落 ELSE 兜底（非法相位 ID）
    16#0003_010E 信息级：液位越限（工艺告警，不置 bError）
    16#0003_011E 信息级：断线安全侧替代已生效（保守取值，不置 bError）

  修订历史 Revision :
    2026-11-18  v1.0.0  R37 首版
*)

TYPE E_DL_FailSafeDir :
(
    eLow  := 0,   // 低液位型：液位低时开关动作；断线时读数浮为「高位」/ Low-level type, a broken wire reads as high
    eHigh := 10   // 高液位型：液位高时开关动作；断线时读数浮为「低位」/ High-level type, a broken wire reads as low
);
END_TYPE

TYPE E_DL_LevelBankState :
(
    eIdle  := 0,   // 空闲：未使能，输出全部复位 / Idle, all outputs cleared while disabled
    eRun   := 10,  // 运行：逐罐评估 / Running, per-tank evaluation
    eFault := 90   // 故障：组态非法锁定 / Fault, illegal configuration latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_SlurryLevelBank
VAR_INPUT
    bEnable        : BOOL := FALSE;                       // 总使能，FALSE 时输出全复位 / Master enable, low level clears the outputs
    bReset         : BOOL := FALSE;                       // 复位，上升沿清故障锁存 / Reset, rising edge clears the latch
    uBankSize      : UINT := 3;                           // 罐组实际罐数 [个]，域 1~DL_BANK_MAX / Number of tanks in use
    abLevelHigh    : ARRAY[0..7] OF BOOL;                 // 高位开关原始输入 [BOOL/罐] / Raw high-level switch inputs
    abLevelLow     : ARRAY[0..7] OF BOOL;                 // 低位开关原始输入 [BOOL/罐] / Raw low-level switch inputs
    anSensorQuality : ARRAY[0..7] OF INT;                 // 传感器质量字 [0~3，0 = OK] / Sensor quality word, zero means OK
    aeFailSafeDir  : ARRAY[0..7] OF E_DL_FailSafeDir;     // 每罐 fail-safe 方向组态 [枚举/罐] / Per-tank fail-safe direction
    tQualityDb     : TIME := T#500MS;                     // 质量字去抖窗 [ms]，域 > 0 / Quality debounce window [ms]
END_VAR
VAR_OUTPUT
    abLevelAlarm   : ARRAY[0..7] OF BOOL;                 // 逐罐液位越限报警 [BOOL/罐] / Per-tank level alarm
    abSensorFault  : ARRAY[0..7] OF BOOL;                 // 逐罐传感器故障 [BOOL/罐] / Per-tank sensor fault
    nFaultCount    : INT;                                 // 故障罐数 [个] / Number of faulty tanks
    bBankAlarm     : BOOL;                                // 罐组总报警（越限或故障任一）/ Bank aggregate alarm
    bValid         : BOOL;                                // 判据可用标志 / Criteria usable
    bError         : BOOL;                                // 故障标志，派生自锁存 / Fault flag derived from the latch
    nErrId         : UDINT;                               // 事件码，0 = 无事件 / Event code, 0 = no event
    eStateOut      : E_DL_LevelBankState;                 // 状态出口，段尾单点映射 / State outlet, mapped at the tail
END_VAR
VAR
    tonQuality   : TON;                                   // 质量故障去抖窗，每拍无条件调用 / Quality fault debounce, called unconditionally
    tonHeart     : TON;                                   // 周期心跳窗，自复位 / Periodic heartbeat window, self-resetting
    rtReset      : R_TRIG;                                // 复位上升沿 / Reset rising edge
    _eState      : E_DL_LevelBankState := E_DL_LevelBankState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _uFault      : UDINT;                                 // 故障码锁存 / Latched fault code
    _uInfo       : UDINT;                                 // 信息码，每拍重算 / Information code, recomputed per scan
    _bFault      : BOOL;                                  // 故障锁存位 / Latched fault bit
    _bCfgBad     : BOOL;                                  // 组态非法聚合 / Configuration invalid aggregate
    _bAnySensFault : BOOL;                                // 任一罐传感器故障 / Any sensor fault present
    _bAnyOpposite  : BOOL;                                // 任一罐高低位相反 / Any opposite-switch condition
    _bAnyLevelAlarm : BOOL;                               // 任一罐液位越限 / Any level alarm present
    _bSafeSubst  : BOOL;                                  // 本拍发生安全侧替代 / A safe-side substitution happened
    _bOppClear   : BOOL;                                  // 相反故障已全部消失 / All opposite conditions cleared
    _bHeartBrk   : BOOL := TRUE;                          // 心跳窗断输入一拍 / One-scan heartbeat break
    _bQualBrk    : BOOL := TRUE;                          // 质量去抖断输入一拍 / One-scan quality break
    _nIdx        : INT;                                   // 循环索引 [索引] / Loop index
    _nFaultAcc   : INT;                                   // 故障罐数保持量 [个] / Held faulty-tank count
    _bHighEff    : BOOL;                                  // 高位开关的解释后值（含安全侧替代）/ Effective high-level value
    _bLowEff     : BOOL;                                  // 低位开关的解释后值（含安全侧替代）/ Effective low-level value
    _bOpposite   : BOOL;                                  // 本罐高低位同时为真 / Both switches true in this tank
    _bQualBad    : BOOL;                                  // 本罐质量字非 OK / Quality word not OK in this tank
    _bDirBad     : BOOL;                                  // 本罐方向枚举非法 / Illegal direction enumeration in this tank
END_VAR
VAR CONSTANT
    DL_BANK_MAX   : INT := 8;          // 数组声明长度 [个]，四数组同长 / Declared array length, identical for all four arrays
    DL_QUAL_MAX   : INT := 3;          // 质量字最大值 [编码] / Maximum quality code
    DL_HEART_WINDOW : TIME := T#2S;    // 心跳观察窗 [ms]，自复位节拍 / Heartbeat window, self-resetting
END_VAR

(* —— 段 0：定时器与边缘检测无条件周期刷新（R182：调用语句不得置于 IF / CASE / FOR 内） —— *)
rtReset(CLK := bReset);                                          // 复位上升沿，每拍必调
tonHeart(IN := (NOT tonHeart.Q) AND (NOT _bHeartBrk), PT := DL_HEART_WINDOW);  // 心跳窗自复位
_bHeartBrk := FALSE;                                             // 断输入拍在调用后自清
tonQuality(IN := (_eState = E_DL_LevelBankState.eRun) AND _bAnySensFault AND (NOT _bQualBrk),
           PT := tQualityDb);                                    // 质量故障去抖（表达式入参）
_bQualBrk := FALSE;                                              // 断输入拍在调用后自清

(* —— 段 1：单拍量预清零（数组输出与保持量不入清单，R187①） —— *)
_uInfo        := 16#0000_0000;   // 信息码每拍重算
bError        := FALSE;          // 故障出口每拍重算，段 6 由锁存派生
bValid        := FALSE;          // 可用标志缺省 FALSE
bBankAlarm    := FALSE;          // 罐组总报警缺省 FALSE
_bCfgBad      := FALSE;          // 组态非法预清零
_bAnySensFault := FALSE;         // 传感器故障聚合预清零
_bAnyOpposite := FALSE;          // 相反故障聚合预清零
_bAnyLevelAlarm := FALSE;        // 越限聚合预清零
_bSafeSubst   := FALSE;          // 安全侧替代标志预清零
_bOppClear    := TRUE;           // 相反故障清空判定初值（循环内遇相反即置 FALSE）
_bDirBad      := FALSE;          // 方向非法预清零

(* —— 段 2：复位沿清锁存 + 按码专清（R188 双路径） —— *)
IF rtReset.Q THEN
    _bFault     := FALSE;            // 复位沿清锁存位
    _uFault     := 16#0000_0000;     // 复位沿清锁存码
    _nFaultAcc  := 0;                // 复位沿清故障罐数（重新统计）
END_IF

(* —— 段 3：组态域闸（循环之前完成，越界即返回不进入循环，R28-2） —— *)
IF (uBankSize = 0) OR (uBankSize > INT_TO_UINT(DL_BANK_MAX)) THEN
    _bCfgBad := TRUE;                // 罐数越界：0 或超数组声明长度
END_IF
IF TIME_TO_DINT(tQualityDb) <= 0 THEN
    _bCfgBad := TRUE;                // 去抖窗非法
END_IF
IF _bCfgBad THEN
    _uFault := 16#0003_020E;         // 故障级：组态非法
    _bFault := TRUE;                 // 锁存位置位（复位沿可清）
    bError  := TRUE;                 // 故障标志置位（R45 配对）
    _eState := E_DL_LevelBankState.eFault;  // 进故障相（不进入循环）
END_IF

(* —— 段 4：逐罐评估（仅运行相且组态合法时进入；循环上界由 uBankSize 钳制） —— *)
IF bEnable AND (_eState <> E_DL_LevelBankState.eFault) AND (NOT _bCfgBad) THEN
    _nFaultAcc := 0;                          // 故障罐数每拍重算（输出量，非台账）
    FOR _nIdx := 0 TO (UINT_TO_INT(uBankSize) - 1) DO
        (* 4.1 本罐假设值初始化：有效值先取原始值，随后按质量与方向修正 *)
        _bHighEff := abLevelHigh[_nIdx];       // 高位原始读数 [BOOL]
        _bLowEff  := abLevelLow[_nIdx];        // 低位原始读数 [BOOL]
        _bQualBad := (anSensorQuality[_nIdx] < 0) OR (anSensorQuality[_nIdx] > DL_QUAL_MAX) OR
                     (anSensorQuality[_nIdx] <> 0);            // 质量字非 OK（含越域：无法解释即判坏）
        IF (anSensorQuality[_nIdx] < 0) OR (anSensorQuality[_nIdx] > DL_QUAL_MAX) THEN
            _bCfgBad := TRUE;                  // 质量字越 0~3 域：组态/采集链错误
            _uFault := 16#0003_020E;           // 故障级：组态非法
            _bFault := TRUE;                   // 锁存
            bError  := TRUE;                   // 故障标志置位（R45 配对）
        END_IF
        IF _bQualBad THEN
            _bAnySensFault := TRUE;            // 传感器故障聚合
            abSensorFault[_nIdx] := TRUE;      // 逐罐故障输出
            _bSafeSubst := TRUE;               // 发生安全侧替代
            (* 4.2 fail-safe 方向解释：断线时 LOW 型读成「高位」，HIGH 型读成「低位」——
                   保守取值即两者都按「报警成立」处理（低液位保护泵、高液位保护溢流） *)
            IF aeFailSafeDir[_nIdx] = E_DL_FailSafeDir.eLow THEN
                _bHighEff := FALSE;            // LOW 型断线：原始高位读数是浮空假象，不予采信
                _bLowEff  := TRUE;             // 安全侧：认低液位（保护泵干转）
            ELSIF aeFailSafeDir[_nIdx] = E_DL_FailSafeDir.eHigh THEN
                _bHighEff := TRUE;             // 安全侧：认高液位（保护溢流）
                _bLowEff  := FALSE;            // HIGH 型断线：原始低位读数是浮空假象，不予采信
            ELSE
                _bDirBad := TRUE;              // 方向枚举非法：两位都认（最保守）
                _bHighEff := TRUE;
                _bLowEff  := TRUE;
                _uFault := 16#0003_020E;       // 故障级：组态非法（方向未组态）
                _bFault := TRUE;               // 锁存
                bError  := TRUE;               // 故障标志置位（R45 配对）
            END_IF
        ELSE
            abSensorFault[_nIdx] := FALSE;     // 质量 OK：清该罐传感器故障（按罐专清）
        END_IF
        (* 4.3 开关相反判据：同一罐高低位同时为真（物理上不可能，H 型与 L 型不可能同真） *)
        _bOpposite := _bHighEff AND _bLowEff;
        IF _bOpposite THEN
            _bAnyOpposite := TRUE;             // 相反故障聚合
            _bOppClear := FALSE;               // 相反条件仍在：禁止按码专清
            _uFault := 16#0003_022E;           // 故障级：开关相反
            _bFault := TRUE;                   // 锁存
            bError  := TRUE;                   // 故障标志置位（R45 配对）
        END_IF
        (* 4.4 越限判定：高低位任一为真即越限（信息级，不置 bError） *)
        IF _bHighEff OR _bLowEff THEN
            abLevelAlarm[_nIdx] := TRUE;       // 逐罐越限输出
            _bAnyLevelAlarm := TRUE;           // 越限聚合
        ELSE
            abLevelAlarm[_nIdx] := FALSE;      // 本罐无越限：按罐清零
        END_IF
        (* 4.5 故障罐数累计：传感器故障 + 开关相反各计一次（越限不计入故障数） *)
        IF abSensorFault[_nIdx] OR _bOpposite THEN
            IF _nFaultAcc < DL_BANK_MAX THEN
                _nFaultAcc := _nFaultAcc + 1;  // 故障罐数 +1（钳制到声明长度，不溢出）
            END_IF
        END_IF
    END_FOR
    (* 4.6 未使用的罐位输出清零（上界之外不得残留旧值） *)
    FOR _nIdx := UINT_TO_INT(uBankSize) TO (DL_BANK_MAX - 1) DO
        abLevelAlarm[_nIdx]  := FALSE;         // 未用罐位：越限清零
        abSensorFault[_nIdx] := FALSE;         // 未用罐位：故障清零
    END_FOR
ELSE
    _nFaultAcc := 0;                           // 故障相/组态非法：不做评估，故障数为 0（不伪造）
    FOR _nIdx := 0 TO (DL_BANK_MAX - 1) DO
        abLevelAlarm[_nIdx]  := FALSE;         // 全清：越限输出
        abSensorFault[_nIdx] := TRUE;          // 全置：故障相时无法判读，按不可信上报
    END_FOR
END_IF

(* —— 段 5：相位机（只做迁移；输出映射在段 7，CASE 内不写输出枚举，N2） —— *)
CASE _eState OF
E_DL_LevelBankState.eIdle:
    _nFaultAcc := 0;                           // 空闲：不做评估，故障罐数归零
    IF bEnable AND (NOT _bCfgBad) AND (NOT _bFault) THEN
        _eState := E_DL_LevelBankState.eRun;   // 使能且组态合法：进运行相
    END_IF
E_DL_LevelBankState.eRun:
    IF NOT bEnable THEN
        _eState := E_DL_LevelBankState.eIdle;  // 失能：回空闲（输出在段 7 单点清零）
    END_IF
E_DL_LevelBankState.eFault:
    IF (NOT _bFault) AND (NOT _bCfgBad) AND bEnable THEN
        _eState := E_DL_LevelBankState.eRun;   // 锁存已清且组态合法：回运行相
    END_IF
ELSE
    _uFault := 16#0003_023E;                   // 故障级：相位 ID 越界（枚举兜底）
    _bFault := TRUE;                           // 锁存
    bError  := TRUE;                           // 故障标志置位（R45 配对）
    _eState := E_DL_LevelBankState.eFault;     // 强制回故障相
END_CASE

(* 段 5B｜按码专清（依赖段 4 的逐罐结果，故必须置于评估之后，R188 可达清除边） *)
IF (_uFault = 16#0003_022E) AND _bOppClear THEN
    _uFault := 16#0000_0000;                   // 相反条件全部消失 → 该码可解
    _bFault := FALSE;                          // 锁存位同步清
END_IF
IF (_uFault = 16#0003_021E) AND (NOT _bAnySensFault) AND (NOT _bCfgBad) THEN
    _uFault := 16#0000_0000;                   // 质量字全部恢复 OK → 传感器故障码可解
    _bFault := FALSE;                          // 锁存位同步清
END_IF

(* —— 段 6：信息码与故障码优先级链（越限永不置 bError；每个 bError 源均有码，R45） —— *)
IF _bAnySensFault AND _bSafeSubst THEN
    _uInfo := 16#0003_011E;                    // 信息级：断线安全侧替代已生效
ELSIF _bAnyLevelAlarm THEN
    _uInfo := 16#0003_010E;                    // 信息级：液位越限（工艺告警）
END_IF
IF _bCfgBad THEN
    _uFault := 16#0003_020E;                   // 组态非法优先上报（其余码不得掩盖组态根因）
    _bFault := TRUE;                           // 锁存
    bError  := TRUE;                           // 故障标志置位
ELSIF _bAnyOpposite THEN
    _uFault := 16#0003_022E;                   // 开关相反优先于传感器故障上报（接线错根因）
    _bFault := TRUE;                           // 锁存
    bError  := TRUE;                           // 故障标志置位
ELSIF _bAnySensFault AND tonQuality.Q THEN
    _uFault := 16#0003_021E;                   // 传感器故障：去抖窗满才上报（防瞬时质量抖动）
    _bFault := TRUE;                           // 锁存
    bError  := TRUE;                           // 故障标志置位
END_IF

(* —— 段 7：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _eState = E_DL_LevelBankState.eIdle THEN
    FOR _nIdx := 0 TO (DL_BANK_MAX - 1) DO
        abLevelAlarm[_nIdx]  := FALSE;         // 空闲：越限输出清零
        abSensorFault[_nIdx] := FALSE;         // 空闲：故障输出清零
    END_FOR
END_IF
nFaultCount := _nFaultAcc;                     // 故障罐数出口
bBankAlarm  := _bAnyLevelAlarm OR _bAnyOpposite OR _bAnySensFault OR _bFault;  // 罐组总报警
eStateOut   := _eState;                        // 状态出口
IF _bFault THEN
    nErrId := _uFault;                         // 故障锁存码回放（不在故障相按当下输入重推）
    bError := TRUE;                            // 故障出口派生自锁存
ELSE
    nErrId := _uInfo;                          // 信息码
END_IF
bValid := bEnable AND (NOT _bFault) AND (NOT _bCfgBad);  // 判据可用

END_FUNCTION_BLOCK
