(*
    FB_DL_SipLineSterilSeq —— 管路 SIP 蒸汽灭菌顺控（排凝 → 升温 → 保温窗 → 冷却 → 放行）
    ------------------------------------------------------------------
    组件名称  : FB_DL_SipLineSterilSeq
    分类      : DL_Process / Sterilization
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 借鉴组织 —— T2-2 LBP 基础工艺（矩阵行 163）：仅借鉴
                「命令 → 监视 → 判定」三段分层骨架的公开语义；次源 T2-8
                ISA-88 相语义公开条款（相 / 状态命名惯例）；clean-room
                声明 —— 保温窗断点重计与温度判据 100% 自有，零代码行复制；
                SIP 121 ℃ 最低承诺属公开工程惯例条款（下界 100 ℃ 为本件
                组态锁存闸，可调）。
    平台      : 纯 IEC 61131-3（ENUM + CASE + TON / R_TRIG + TIME 算术），
                CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R72 构建轮 · 批 4 · 序号 12）
    ------------------------------------------------------------------
    功能说明  : 管路蒸汽 SIP（Sterilize-In-Place）连续工艺段顺控：
                eIdle →（bEn ∧ 组态闸）eDrain（排凝，bDrainDone 反馈或
                tDrainTimeout 超时）→ eHeatUp（开蒸汽升温，fTempC 达
                fHoldTempSet 迁入）→ eHold（保温窗 TON 计时）→ eCooldown
                （关蒸汽，温度回落确认）→ eDone（bSterilized 放行保持）→
                eIdle（批界）。
                安全核心口径：
                ① fTempC 非有限（探头断线）→ **故障锁存 + 双输出立即关断**
                   ——温度状态不明不得放行，宁可重灭菌；
                ② 保温窗断点重计（SIP 无菌保证不容断点续计）：eHold 相内
                   fTempC 跌破 fHoldTempSet（每拍取本拍实时值，R42 本拍
                   复验口径）→ 计时中止回 eHeatUp + 扰动计数 +1，恢复后
                   TON 从零重计——断点续计等于伪造无菌时长，写死禁用；
                ③ fHoldTempSet 越承诺段（< 100 ℃）→ 组态锁存（SIP 公开
                   最低承诺 121 ℃ 工程惯例，下界闸定 100 ℃ 并留调参会空间
                   ——承诺下界以常量声明，单探头承诺段声明见边界八）；
                ④ 失能 → 双输出（bDrainCmd / bSteamCmd）清零 + bSterilized
                   撤销 + 状态回 eIdle（停机相输出清零，R57）；故障锁存保留，
                   复位沿解除；
                ⑤ 迁入 eHold 相与每拍判温均取本拍实时值（迁入拍即计时使能，
                   无跨拍陈旧判据）。
                冷却放行口径：eCooldown 以 fTempC < fHoldTempSet 确认回落
                （防高温放行烫尾），回落即 eDone；bSterilized 为**保持型**
                放行位（批界 = bEn 撤除或复位沿时清除）。
    错误码    : 16#0005_0640 工艺温度非有限（探头断线 / ADC 故障），双输出
                            立即关断，锁存至复位沿 —— 故障级
                16#0005_0641 排凝超时（eDrain 驻留超 tDrainTimeout），锁存
                            至复位沿 —— 故障级
                16#0005_0642 保温设定越承诺段（fHoldTempSet < 100 ℃ 或非
                            有限），锁存至复位沿 —— 故障级
                16#0005_0643 保温窗 / 排凝超时组态非正（tHoldTime /
                            tDrainTimeout <= 0），锁存至复位沿 —— 故障级
                加码反证句（R90）：0640 由「双输出关断 + eHealth 语义温度
                断线」唯一观测；0641 / 0642 / 0643 成因互斥且调用方可自证
                （反馈时序 / 组态表），输出组合（同为 eFault + bError）不可
                互换还原成因，维修动作各异，故各立一码；保温跌破扰动以
                uDisturbCount 专位观测（R90 不加码：扰动事件已有独立可观
                测出口，不重复发码）。
    码位总账  : 16#0005_0640 用 ｜ 16#0005_0641 用 ｜ 16#0005_0642 用 ｜
                16#0005_0643 用
                （0630 / 0631 已由 FB_DL_RejectBlowCtrl 占用，本件不占）
    边界与披露: 一 双 TON（tonDrain / tonHold）与 R_TRIG（rtReset）每拍
                   **无条件调用**（规则 ⑦），IN 为显式条件变量（R145 相驻留
                   口径：tonDrain IN = 排凝相驻留，tonHold IN = 保温相驻留
                   ∧ 本拍温度达标）；
                二 零全局变量、零 VAR_EXTERNAL、零物理地址；
                三 归属 Ownership：E_DL_SipPhase 属主为本文件（全库唯一定义，
                   R264），引用件只引用不重声明；
                四 状态机 ENUM + CASE 必带 ELSE 兜底（非法枚举值 → eFault
                   锁存）+ 段 5b 统一故障迁入闸（R274 迁入完备性）；
                五 域闸逐项点名（R272）：fTempC（非有限闸）+ fHoldTempSet
                   （非有限与承诺段闸）全部浮点引脚入闸；
                六 时间量纲口径：tHoldTime / tDrainTimeout 均为 TIME 引脚
                   （内部毫秒），保温剩余 uHoldRemain 以秒发布（TIME_TO_DINT
                   毫秒差 ÷ 常量除子 1000，零除法面，R382 常量除子级联）；
                七 单探头承诺段声明：本件按单工艺温度探头承诺（多点冷点
                   归上位编排，数组版不立防拆件凑数）；fHoldTempSet 默认
                   121.0 ℃ 仅为 SIP 工程惯例参考值，非承诺；
                八 分工声明：FB_DL_CipCleaningSeq（化学清洗顺控）、
                   FB_DL_AutoclaveSterilSeq（灭菌釜批次）、
                   FB_DL_TunnelPasteurizerSeq（隧道巴氏）——本件专管
                   **管路蒸汽 SIP 连续工艺段**，互引不互代；
                九 复位沿作用域（R311）：清全部锁存 + 清锁存码 + 迁 eIdle +
                   清 bSterilized（批界复位）+ 清扰动计数（批次台账随批清），
                   **不清**自动统计类（本件无）；
                十 依赖声明：仅 Standard.library（TON / R_TRIG），零厂商
                   方言。
    验收向量  : V1 正常批次：排凝反馈 → 升温达标 → 保温 tHoldTime → 冷却
                回落 → bSterilized 保持，uDisturbCount = 0；
                V2 保温中跌破设定 → 回 eHeatUp + uDisturbCount + 1，恢复后
                保温从零重计（断点重计口径自证）；
                V3 fTempC = NaN → 0640 锁存 + 双输出关断；
                V4 fHoldTempSet = 90 ℃ → 0642 锁存；V5 tHoldTime = T#0S →
                0643 锁存；V6 排凝超时 → 0641 锁存；V7 失能 → 双输出清零 +
                bSterilized 撤销；V8 复位沿 → 解锁回 eIdle。
                算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    修订记录  : 2026-11-23 v1.0.0 首次入库（R72 构建轮 · 批 4 · 序号 12）
*)
TYPE E_DL_SipPhase :
(
    eIdle     := 0,                        // 空闲：等使能与组态闸 / idle, waiting for the enable
    eDrain    := 10,                       // 排凝：等反馈或超时 / drain, waiting for the feedback
    eHeatUp   := 20,                       // 升温：开蒸汽等达标 / heat up, the steam on
    eHold     := 30,                       // 保温窗：TON 计时，跌破重计 / hold, the timed window
    eCooldown := 40,                       // 冷却：关蒸汽等回落 / cooldown, the steam off
    eDone     := 50,                       // 放行：bSterilized 保持相 / done, the release phase
    eFault    := 60                        // 故障：锁存待复位 / fault, latched until the reset
);
END_TYPE

FUNCTION_BLOCK FB_DL_SipLineSterilSeq
VAR_INPUT
    fTempC        : LREAL;                 (* 工艺温度探头（单探头承诺段），[摄氏度]，非有限即探头故障 / the process temperature in degC *)
    bDrainDone    : BOOL := FALSE;         (* 排凝完成反馈，[标志]，引脚注入 / the drain done feedback *)
    fHoldTempSet  : LREAL := 121.0;        (* 保温承诺温度，[摄氏度]，禁 < 100 / 非有限（默认 121 为 SIP 惯例参考值）/ the hold temperature setpoint *)
    tHoldTime     : TIME := T#1800S;       (* 保温窗，[ms]，禁非正 / the hold window duration *)
    tDrainTimeout : TIME := T#300S;        (* 排凝超时，[ms]，禁非正 / the drain timeout *)
    bEn           : BOOL := FALSE;         (* 使能，[标志]，FALSE 双输出清零回 eIdle（锁存保留）/ the enable *)
    bReset        : BOOL := FALSE;         (* 故障复位，[标志]，上升沿唯一解除 / the fault reset *)
END_VAR
VAR_OUTPUT
    bDrainCmd   : BOOL := FALSE;           (* 排凝指令出口，[标志]，故障 / 失能为 FALSE / the drain command outlet *)
    bSteamCmd   : BOOL := FALSE;           (* 蒸汽指令出口，[标志]，故障 / 失能为 FALSE（安全侧关断）/ the steam command outlet *)
    bSterilized : BOOL := FALSE;           (* 灭菌放行出口（保持型，批界清除）[标志] / the sterilized release outlet *)
    uHoldRemain : UDINT := 0;              (* 保温剩余倒计时（HMI），[秒]，非保温相为 0 / the hold remaining seconds *)
    uDisturbCount: UDINT := 0;             (* 保温跌破扰动计数（批界复位）[次] / the hold disturbance count *)
    eState      : E_DL_SipPhase := E_DL_SipPhase.eIdle; // 主状态机当前态 [状态] / the current state
    bError      : BOOL := FALSE;           (* 故障标志，与锁存同源（R191）/ the fault flag from the latch *)
    nErrCode    : UDINT := 16#0000_0000;   (* 错误码，0 = 正常，故障锁存回放（R187）/ the error id *)
END_VAR
VAR
    _bInit      : BOOL := FALSE;           (* 首拍初始化标志（R310）/ the first scan flag *)
    _eState     : E_DL_SipPhase := E_DL_SipPhase.eIdle; // 内部状态寄存器 / the internal state register
    _bFault     : BOOL := FALSE;           (* 故障锁存副本，仅复位沿解除 / the fault latch copy *)
    _nCodeLatch : UDINT := 0;              (* 锁存成因码，故障期回放 / the latched cause code *)
    _bCfgBad    : BOOL := FALSE;           (* 组态非法标志（逐拍重算，仅用于首次锁存）/ the config fault flag *)
    _bTInBad    : BOOL := FALSE;           (* 温度非有限标志（逐拍重算，R272 闸）/ the temperature invalid flag *)
    _bTempOk    : BOOL := FALSE;           (* 本拍温度达标实时判据（R42 本拍复验）/ the live temperature verdict *)
    _bDrain     : BOOL := FALSE;           (* 排凝指令内部位（统一出口映射）/ the internal drain bit *)
    _bSteam     : BOOL := FALSE;           (* 蒸汽指令内部位（统一出口映射）/ the internal steam bit *)
    _bReleased  : BOOL := FALSE;           (* 放行内部锁存（eDone 相保持）/ the internal release latch *)
    nRemainMs   : DINT := 0;               (* 保温剩余毫秒中间量 [ms] / the remaining milliseconds temporary *)
    rtReset     : R_TRIG;                  (* 复位沿实例（无条件调用）/ the reset edge instance *)
    tonDrain    : TON;                     (* 排凝超时看门狗（无条件调用）/ the drain watchdog timer *)
    tonHold     : TON;                     (* 保温窗计时（无条件调用）/ the hold window timer *)
END_VAR
VAR CONSTANT
    DL_SIP_CODE_TEMP : UDINT := 16#0005_0640; // 温度非有限故障码 [码] / the probe fault code
    DL_SIP_CODE_DRAIN: UDINT := 16#0005_0641; // 排凝超时故障码 [码] / the drain timeout code
    DL_SIP_CODE_SET  : UDINT := 16#0005_0642; // 保温设定越承诺段故障码 [码] / the setpoint fault code
    DL_SIP_CODE_TIME : UDINT := 16#0005_0643; // 时间组态非正故障码 [码] / the time config fault code
    DL_SIP_TSETMIN   : LREAL := 100.0;       (* 保温承诺温度下界（SIP 公开最低承诺 121 ℃，下界闸 100 ℃ 可调参会）[摄氏度] / the setpoint promise lower bound *)
    DL_SIP_TZERO     : LREAL := 0.0;         (* 浮点零哨兵 [摄氏度] / the float zero sentinel *)
    DL_SIP_TTIMEZERO : TIME := T#0S;        (* 零时长哨兵 [ms] / the zero duration sentinel *)
    DL_SIP_MS_SEC    : DINT := 1000;        (* 毫秒到秒常量除子（R382 级联口径）[ms/s] / the constant milliseconds per second divisor *)
    DL_SIP_ZERO      : UDINT := 0;          (* 无符号零哨兵 [码或秒或次] / the unsigned zero sentinel *)
    DL_SIP_ONE       : UDINT := 1;          (* 计数步进 [次] / the count step *)
    DL_SIP_CMAX      : UDINT := 2147483000; (* 扰动计数饱和上限（防回绕）[次] / the disturbance count saturation cap *)
END_VAR

// 段 0｜复位沿无条件调用（规则 ⑦）/ segment 0, the unconditional reset edge refresh
rtReset(CLK := bReset);                    // 每拍无条件刷新 / refreshed every scan

// 段 1｜首拍初始化与出口内部位预清（R310 / R256）/ segment 1, the first scan init and the presets
IF NOT _bInit THEN                         // 首拍一拍 / the first scan
    _bInit := TRUE;                        // 置首拍标志 / raise the first scan flag
    _bFault := FALSE;                      // 故障锁存显式清零 / clear the fault latch explicitly
    _eState := E_DL_SipPhase.eIdle;        // 状态显式落空闲 / place the state to idle
END_IF

// 段 2｜域闸（R272 全枚举：fTempC 非有限闸 + fHoldTempSet 非有限与承诺段闸）/ segment 2, the domain gates
_bTInBad := (fTempC <> fTempC) OR ((fTempC - fTempC) <> DL_SIP_TZERO); // 温度非有限（R79 双判）/ the temperature non finite
_bCfgBad := (fHoldTempSet <> fHoldTempSet) OR ((fHoldTempSet - fHoldTempSet) <> DL_SIP_TZERO) // 设定非有限 / the setpoint non finite
         OR (fHoldTempSet < DL_SIP_TSETMIN) // 设定越承诺段下界 / the setpoint under the promise
         OR (tHoldTime <= DL_SIP_TTIMEZERO) // 保温窗非正 / a non positive hold window
         OR (tDrainTimeout <= DL_SIP_TTIMEZERO); // 排凝超时非正 / a non positive drain timeout

// 段 3｜本拍实时温度判据（R42：迁入与驻留判温均取本拍值；NaN 不许当冷值漏判）/ segment 3, the live temperature verdict
IF (NOT _bTInBad) AND (NOT _bCfgBad) THEN  // 双闸通过才判 / both gates passed
    _bTempOk := fTempC >= fHoldTempSet;    // 达标本拍实时值 / the live verdict
ELSE                                       // 闸未通过 / the gates failed
    _bTempOk := FALSE;                     // 达标判据强制假（安全侧）/ force the verdict false
END_IF

// 段 4｜复位沿与首次成因锁存（复位沿唯一解除，R188；故障期不重推断，R189；组态根因优先）/ segment 4, the reset edge and the first cause latch
IF rtReset.Q THEN                          // 复位上升沿 / the reset rising edge
    _bFault := FALSE;                      // 清故障锁存（恒可达，R152 自证）/ clear the fault latch
    _nCodeLatch := DL_SIP_ZERO;            // 清锁存码 / clear the latched code
    _eState := E_DL_SipPhase.eIdle;        // 迁回空闲 / back to idle
    _bReleased := FALSE;                   // 清放行内部锁存（批界复位）/ clear the release latch
    uDisturbCount := DL_SIP_ZERO;          // 清扰动计数（批次台账随批清，作用域声明边界九）/ clear the disturbance count
END_IF
IF NOT _bFault THEN                        // 未锁存才登记成因 / register only while not latched
    IF _bCfgBad THEN                       // 组态非法（根因优先归因）/ the config fault first
        _bFault := TRUE;                   // 置锁存 / latch
        _nCodeLatch := DL_SIP_CODE_SET;    // 登记设定码 / register the setpoint code
        IF (tHoldTime <= DL_SIP_TTIMEZERO) OR (tDrainTimeout <= DL_SIP_TTIMEZERO) THEN // 时间组态单独归因（R190 成因独立码）/ the time config attribution
            _nCodeLatch := DL_SIP_CODE_TIME; // 登记时间码 / register the time code
        END_IF
    ELSIF _bTInBad THEN                    // 温度非有限（状态不明不得放行，直接锁存）/ the probe fault
        _bFault := TRUE;                   // 置锁存 / latch
        _nCodeLatch := DL_SIP_CODE_TEMP;   // 登记探头码 / register the probe code
    END_IF
END_IF

// 段 5｜主状态机（ENUM + CASE，ELSE 兜底；迁入安全相带全量闸位复检，R274）/ segment 5, the main state machine
CASE _eState OF

    E_DL_SipPhase.eIdle:                   // 空闲相 / the idle phase
        _bDrain := FALSE;                  // 双输出内部位清零（R57）/ clear the internal bits
        _bSteam := FALSE;                  // 双输出内部位清零 / clear the internal bits
        IF bEn AND (NOT _bFault) AND (NOT _bCfgBad) THEN // 使能 ∧ 组态闸（迁入闸位复检，R274）/ the start gate
            _eState := E_DL_SipPhase.eDrain; // 迁入排凝相 / enter the drain phase
        END_IF

    E_DL_SipPhase.eDrain:                  // 排凝相：开排凝等反馈 / the drain phase
        _bDrain := TRUE;                   // 排凝指令 / the drain command
        _bSteam := FALSE;                  // 蒸汽关断 / the steam off
        // 失能或温度失效不在此自行迁出：由段 4 首次成因锁存 + 段 5b 统一迁入闸接管。
        // A disable or a probe loss does not exit here, the unified gates take over.
        IF bDrainDone THEN                 // 排凝完成反馈 / the drain done feedback
            _bDrain := FALSE;              // 撤排凝 / drop the drain command
            _eState := E_DL_SipPhase.eHeatUp; // 迁入升温相 / enter the heat up phase
        ELSIF tonDrain.Q THEN              // 排凝超时（看门狗到时）/ the drain timeout
            _bFault := TRUE;               // 置锁存 / latch the fault
            _nCodeLatch := DL_SIP_CODE_DRAIN; // 登记超时码 / register the timeout code
        END_IF

    E_DL_SipPhase.eHeatUp:                 // 升温相：开蒸汽等达标（本拍实时判温，R42）/ the heat up phase
        _bDrain := FALSE;                  // 排凝撤 / drop the drain
        _bSteam := TRUE;                   // 蒸汽开 / the steam on
        IF _bTInBad THEN                   // 温度失效（关断由故障路径统一执行）/ the probe loss
            _bFault := TRUE;               // 置锁存 / latch
            _nCodeLatch := DL_SIP_CODE_TEMP; // 登记探头码 / register the probe code
        ELSIF _bTempOk THEN                // 本拍达标（实时值，无跨拍陈旧判据）/ the live verdict
            _eState := E_DL_SipPhase.eHold; // 迁入保温相（迁入拍即计时使能）/ enter the hold phase
        END_IF

    E_DL_SipPhase.eHold:                   // 保温相：TON 计时，跌破重计（断点重计口径）/ the hold phase
        _bSteam := TRUE;                   // 蒸汽保持 / the steam holds
        IF _bTInBad THEN                   // 温度失效 / the probe loss
            _bFault := TRUE;               // 置锁存 / latch
            _nCodeLatch := DL_SIP_CODE_TEMP; // 登记探头码 / register the probe code
        ELSIF NOT _bTempOk THEN            // 跌破设定（本拍实时值）：计时中止回升温 + 扰动计数 / the drop below setpoint
            IF uDisturbCount < DL_SIP_CMAX THEN // 饱和闸（防回绕）/ the saturation cap
                uDisturbCount := uDisturbCount + DL_SIP_ONE; // 扰动计数 + 1 / count the disturbance
            END_IF
            _eState := E_DL_SipPhase.eHeatUp; // 回升温相（TON IN 随相撤自动清零重计）/ back to heat up
        ELSIF tonHold.Q THEN               // 保温窗计满（连续无跌破）/ the window elapsed
            _bSteam := FALSE;              // 关蒸汽 / the steam off
            _eState := E_DL_SipPhase.eCooldown; // 迁入冷却相 / enter the cooldown phase
        END_IF

    E_DL_SipPhase.eCooldown:               // 冷却相：关蒸汽等回落确认 / the cooldown phase
        _bSteam := FALSE;                  // 蒸汽关断 / the steam off
        IF _bTInBad THEN                   // 温度失效 / the probe loss
            _bFault := TRUE;               // 置锁存 / latch
            _nCodeLatch := DL_SIP_CODE_TEMP; // 登记探头码 / register the probe code
        ELSIF NOT _bTempOk THEN            // 回落确认（复用本拍达标判据的补集，双闸已过才可比）/ the fall below confirmed
            _bReleased := TRUE;            // 放行内部锁存 / latch the release
            _eState := E_DL_SipPhase.eDone; // 迁入完成相 / enter the done phase
        END_IF

    E_DL_SipPhase.eDone:                   // 完成相：bSterilized 保持（批界清除）/ the done phase
        _bSteam := FALSE;                  // 蒸汽保持关断 / the steam off
        IF NOT bEn THEN                    // 批界：失能（复位沿已由段 4 先行处理）/ the batch boundary on disable
            _bReleased := FALSE;           // 清放行 / clear the release
            _eState := E_DL_SipPhase.eIdle; // 迁回空闲 / back to idle
        END_IF

    E_DL_SipPhase.eFault:                  // 故障相：双输出关断等复位沿 / the fault phase
        _bDrain := FALSE;                  // 排凝关断 / the drain off
        _bSteam := FALSE;                  // 蒸汽关断（安全侧）/ the steam off
        _bReleased := FALSE;               // 放行撤销（故障期不放行）/ the release withdrawn
        IF NOT _bFault THEN                // 锁存已清才迁出 / the exit after the latch cleared
            _eState := E_DL_SipPhase.eIdle; // 迁回空闲 / back to idle
        END_IF

    ELSE                                   // 非法枚举值拦截 / the illegal enumeration guard
        _eState := E_DL_SipPhase.eFault;   // 落故障相 / force to the fault phase
        _bFault := TRUE;                   // 置锁存 / latch the fault
        _nCodeLatch := DL_SIP_CODE_TEMP;   // 复用温度码（R90 反证：非法枚举不可达无独立观测需求）/ reuse the probe code

END_CASE

// 段 5b｜故障统一迁入闸（置于状态机之后，R274 迁入完备性）/ segment 5b, the unified fault entry gate
IF _bFault AND (_eState <> E_DL_SipPhase.eFault) THEN // 已锁存但不在故障相 / latched but not in the fault phase
    _eState := E_DL_SipPhase.eFault;       // 任何相检出故障一律落故障相 / any phase with a latch lands in the fault phase
END_IF

// 段 5c｜失能停机相输出清零（锁存保留，R57 / R191 声明；eDone 批界已自处理）/ segment 5c, the disable clearing
IF (NOT bEn) AND (_eState <> E_DL_SipPhase.eFault) AND (_eState <> E_DL_SipPhase.eDone) THEN // 失能且不在故障 / 完成相 / disabled
    _eState := E_DL_SipPhase.eIdle;        // 撤工艺回空闲 / back to idle
    _bDrain := FALSE;                      // 双输出清零 / clear the bits
    _bSteam := FALSE;                      // 双输出清零 / clear the bits
    _bReleased := FALSE;                   // 放行撤销 / the release withdrawn
END_IF

// 段 6｜双定时器无条件调用（IN 为相驻留显式条件；tonHold IN 含本拍达标判据，跌破即断计重计）/ segment 6, the unconditional timers
tonDrain(IN := (_eState = E_DL_SipPhase.eDrain) AND bEn AND (NOT _bFault), PT := tDrainTimeout); // 排凝看门狗 / the drain watchdog
tonHold(IN := (_eState = E_DL_SipPhase.eHold) AND _bTempOk AND bEn AND (NOT _bFault), PT := tHoldTime); // 保温计时（跌破即断计）/ the hold timer

// 段 7｜保温剩余倒计时（非保温相为 0；常量除子 1000，零除法面）/ segment 7, the hold remaining countdown
IF _eState = E_DL_SipPhase.eHold THEN      // 保温相内计算 / inside the hold phase
    nRemainMs := TIME_TO_DINT(tHoldTime) - TIME_TO_DINT(tonHold.ET); // 剩余毫秒 / the remaining milliseconds
    IF nRemainMs < 0 THEN                  // 负值防御（饱和为零）/ the negative guard
        nRemainMs := 0;                    // 钳到零 / clamp to zero
    END_IF
    uHoldRemain := DINT_TO_UDINT(nRemainMs / DL_SIP_MS_SEC); // 常量除子秒化 / the constant divisor seconds
ELSE                                       // 非保温相 / the other phases
    uHoldRemain := DL_SIP_ZERO;            // 倒计时清零 / zero the countdown
END_IF

// 段 8｜统一出口（名实双出口同源，R191）/ segment 8, the unified outlet
bDrainCmd := _bDrain AND bEn AND (NOT _bFault); // 排凝出口（失能 / 故障双保险）/ the drain outlet
bSteamCmd := _bSteam AND bEn AND (NOT _bFault); // 蒸汽出口（安全侧关断双保险）/ the steam outlet
bSterilized := _bReleased AND (NOT _bFault); // 放行出口（故障期撤销）/ the release outlet
eState := _eState;                         // 状态出口 / the state outlet
bError := _bFault;                         // 故障标志与锁存同源 / the fault flag from the latch
IF _bFault THEN                            // 故障锁存回放（R187）/ the latched replay
    nErrCode := _nCodeLatch;               // 回放锁存码 / replay the latched code
ELSE                                       // 无事件 / no event
    nErrCode := DL_SIP_ZERO;               // 正常 / ok
END_IF
END_FUNCTION_BLOCK
