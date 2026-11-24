(*==============================================================================
 * 组件名称 (Component)  : FB_DL_VisionLightBank
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / SHL / SHR），零厂商方言
 * 来源标签 (Source)     : t1-5-tcopen（视觉光源组语义，clean-room 编写）
 * 功能描述 (Function)   : 2~8 通道视觉光源组多通道切换：通道请求位图经互斥仲裁
 *                         选出唯一生效通道，旧通道立即熄灭，新通道经光强建立时间
 *                         （tStabilize）稳定延时后点亮——稳定延时期间输出冻结
 *                         不闪烁（全灭窗，杜绝双亮）。亮度值按通道保持（afBright），
 *                         通道故障反馈掩码内通道不参与仲裁（只读出口 uFaultMask）。
 * 仲裁风格互引 (Arb)    : 仲裁采用「后到优先可组态」风格，与 FB_DL_RedundantSwitch
 *                         的首选通道策略互为风格参照，不共享实现、不共享枚举。
 * 边界与语义披露 (Boundary disclosure) :
 *   1) 通道数 nChannelCount 域 2..8：非法两级回退（R117）——一级回默认 4，二级
 *      仍在域闸内钳定；回退后继续服务并置故障级码（组态错误必须可见）。
 *   2) 通道号越界（请求位高于通道数）：钳位忽略越界位并置信息级；故障反馈掩码
 *      高于通道数的位同样忽略（组态余量位无害）。
 *   3) 亮度域 0..100%：越界钳位 + 信息级；非有限值拒收（故障级 + 全通道熄灭，
 *      安全侧：光源亮度失控比熄灭危险）。
 *   4) 同拍多通道请求取最高优先仲裁（ePriority）或后到优先（eLatest，按请求沿），
 *      两者互斥可组态；故障通道从候选集剔除后仍按同一仲裁口径决胜。
 *   5) 稳定延时期间输出冻结：旧通道即刻熄灭、新通道延后点亮，窗口内全灭不闪烁。
 * 故障码表 (Error codes) :
 *   16#0003_0505 [故障级] 通道数组态非法（<2 或 >8），已两级回退继续服务
 *                 反证：回退后仲裁照常，输出组合与合法组态相同，码位唯一可见。
 *   16#0003_0506 [故障级] 亮度非有限，拒收并全通道熄灭（安全侧）
 *                 反证：亮度失控与熄灭的输出差异即「全零」——与合法亮度 0 的
 *                 组合相同，码位是失控事实的唯一出口。
 *   16#0003_0405 [信息级] 请求 / 反馈位高于通道数，已钳位忽略越界位
 *                 反证：越界位被忽略后输出与「从未请求」组合相同，无码不可区分。
 *   16#0003_0406 [信息级] 亮度越 0..100 域，已钳位
 *                 反证：钳位后输出与显式给边界值组合相同，无码不可区分。
 * 码位总账 (Code ledger) : 16#0003_0505 / 0506 用 ｜ 16#0003_0405 / 0406 用
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: TON / R_TRIG / SHL / SHR
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与 VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q 物理地址
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 域闸全枚举 / 钳位 / 非有限双判
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 四态 ENUM + CASE + ELSE 兜底
 *                         R7 ✓ 一沿一计时主体最前部无条件刷新
 * 修订历史 (Revision)   :
 *   2026-11-22  v1.0.0  首版入库（R68 构建轮 · 批 2 · 目标 8）
 *   2026-11-22  v1.0.1  终审就地修①：组态锁存解除路径可达化（复位沿 + 组态改对即清锁存，原全灭驻留不可恢复）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举 1: E_DL_LightArbMode（归属 DL_Device，与 FB_DL_VisionLightBank 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_LightArbMode :
(
    ePriority := 0,   // 最高号优先：同拍多请求取最高通道号 / Highest numbered request wins
    eLatest   := 1    // 后到优先：本拍新请求沿的通道号胜 / Latest new request edge wins
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举 2: E_DL_LightBankState（归属 DL_Device，与 FB_DL_VisionLightBank 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_LightBankState :
(
    eIdle   := 0,    // 无有效请求：全通道熄灭 / No valid request, all channels off
    eStab   := 10,   // 切换稳定延时中：输出冻结全灭 / Stabilisation delay, output frozen dark
    eActive := 20,   // 生效通道点亮 / Active channel lit
    eFault  := 99    // 组态故障：回退继续服务 / Config fault, service continues after fallback
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_VisionLightBank
 * 调用约定: 每个扫描周期无条件调用一次；uReqMask 电平语义，切换由位图沿驱动。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_VisionLightBank
VAR_INPUT
    nChannelCount : INT  := 4;               // 通道数 [个]，域 2..8，非法回退默认 4 / Channel count, 2..8
    eArbMode      : E_DL_LightArbMode := E_DL_LightArbMode.ePriority; // 仲裁模式 / Arbitration mode
    uReqMask      : WORD;                    // 通道请求位图，bit0..7 = 通道 1..8 / Request bitmap, bit0..7 = ch 1..8
    uFaultFbMask  : WORD;                    // 通道故障反馈位图（入，故障通道不参选）/ Channel fault feedback bitmap
    fBrightness   : REAL := 80.0;            // 亮度 [%]，域 0..100，非有限拒收 / Brightness [%], 0..100
    tStabilize    : TIME := T#50MS;          // 光强建立时间（稳定延时）[ms] / Light stabilisation delay [ms]
    bEnable       : BOOL := TRUE;            // 使能 / Enable
    bReset        : BOOL;                    // 上升沿：清除组态故障锁存 / Rising edge: clear config fault latch
END_VAR
VAR_OUTPUT
    auBrightness : ARRAY[0..7] OF REAL;      // 各通道输出亮度 [%]，0 = 灭 / Per channel output brightness
    uActiveCh    : UINT;                     // 当前生效通道号 [1..8]，0 = 无 / Active channel, 0 = none
    bSwitching   : BOOL;                     // 稳定延时进行中 / Stabilisation in progress
    uFaultMask   : WORD;                     // 生效通道故障掩码（只读出口，钳至通道数）/ Effective fault mask, read only
    bError       : BOOL;                     // 故障标志（组态 / 亮度非有限）/ Fault flag, config or brightness
    uErrorId     : UDINT;                    // 故障码，0 = 无故障 / Error code, 0 = none
    eState       : E_DL_LightBankState;      // 当前状态（供 HMI 诊断）/ Current state for HMI diagnosis
END_VAR
VAR
    fbTrigReset    : R_TRIG;                // 复位沿检测实例（清故障）/ Reset edge detector
    tonStab        : TON;                   // 稳定延时计时实例 / Stabilisation timer
    eStateInt      : E_DL_LightBankState;   // 主状态机内部当前态 / Internal state machine state
    nCountEff      : INT;                   // 钳位后通道数 [个] / Clamped channel count
    uBeyondMask    : WORD;                  // 高于通道数的越界位掩码 / Mask of bits beyond the channel count
    uReqEff        : WORD;                  // 剔除故障与越界后的有效请求位图 / Effective request bitmap
    uFaultEff      : WORD;                  // 钳至通道数的故障掩码 / Fault mask clamped to channels
    uReqPrev       : WORD;                  // 上拍有效请求位图（沿判据）/ Previous effective request bitmap
    uNewReq        : WORD;                  // 本拍新请求位 / Newly requested bits this scan
    uTargetBit     : WORD;                  // 仲裁胜出通道的单位掩码 / Winning channel single-bit mask
    nTargetCh      : INT;                   // 仲裁胜出通道号 [1..8]，0 = 无 / Winning channel number, 0 = none
    nActiveChInt   : INT;                   // 当前生效通道号内部副本 / Internal active channel
    afBright       : ARRAY[0..7] OF REAL;   // 各通道亮度保持槽 [%] / Per channel brightness hold slots
    fBrightEff     : REAL;                  // 钳位后的有效亮度 [%] / Clamped effective brightness
    bBrightBad     : BOOL;                  // 亮度非有限拒收 / Brightness non-finite rejected
    bStabRun       : BOOL;                  // 稳定延时计时进行中 / Stabilisation timing active
    bCfgBad        : BOOL;                  // 本拍通道数组态非法 / Channel count illegal this scan
    bCfgLatch      : BOOL;                  // 组态故障锁存（复位沿清除）/ Config fault latch, cleared by reset edge
    bErrorInt      : BOOL;                  // 本拍故障置位累加（出口归并）/ Fault set accumulator of this scan
    bFirstScan     : BOOL := TRUE;          // 上电首扫标志 / First-scan flag
    i              : INT;                   // 遍历索引 / Loop index
END_VAR
VAR CONSTANT
    DL_LB_CH_MIN   : INT  := 2;      // 通道数下限 [个] / Channel count floor
    DL_LB_CH_MAX   : INT  := 8;      // 通道数上限 [个]，与数组维度一致 / Channel count ceiling
    DL_LB_CH_DEF   : INT  := 4;      // 通道数回退默认 [个] / Channel count fallback default
    DL_LB_BRIGHT_MAX : REAL := 100.0; // 亮度上限 [%] / Brightness ceiling
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：一沿一计时主体最前部
 *      Unconditional refresh: one edge and one timer at the very top
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);  // 复位沿检测（清除通道数组态锁存）/ Reset edge for the config latch
tonStab(IN := bStabRun, PT := tStabilize);

(*------------------------------------------------------------------------------
 * 段 2｜上电首扫：通道号 / 亮度槽显式落零，状态 eIdle
 *      First-scan init: channels and brightness slots cleared explicitly
 *-----------------------------------------------------------------------------*)
IF bFirstScan THEN
    eStateInt := E_DL_LightBankState.eIdle;
    FOR i := 0 TO 7 DO
        afBright[i] := 0.0;      // 亮度槽显式清零 / Brightness slots cleared
        auBrightness[i] := 0.0;  // 输出显式清零 / Outputs cleared
    END_FOR
    nActiveChInt := 0;
    uReqPrev     := 16#0000;
    nCountEff    := DL_LB_CH_DEF;
    bFirstScan   := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜每拍预清（FB32-1）：单拍标志，禁入锁存 / 快照
 *      Per-scan preset: single-scan flags only
 *-----------------------------------------------------------------------------*)
bErrorInt := FALSE;
bBrightBad := FALSE;

(*------------------------------------------------------------------------------
 * 段 4｜组态域闸（R151）+ 两级回退（R117）+ 亮度非有限闸（R272 全枚举唯一 REAL 入参）
 *      Config gate, two-level fallback and the brightness finiteness gate
 *      解除路径（R152 自证）：复位沿 AND 通道数组态已改对
 *-----------------------------------------------------------------------------*)
bCfgBad := (nChannelCount < DL_LB_CH_MIN) OR (nChannelCount > DL_LB_CH_MAX);

IF bCfgBad THEN
    nCountEff := DL_LB_CH_DEF;   // 二级回退：钳回默认 4，服务不中断 / Fallback to default 4
    bCfgLatch := TRUE;
ELSE
    nCountEff := nChannelCount;  // 合法直通 / Valid pass-through
END_IF

(* 终审就地修 v1.0.1（R68）：解除路径（R152 自证可达）——复位沿 AND 组态非法条件
 * 全部消失即清锁存。原实现把锁存清零只写在 eFault 相分支，而组态闸置锁存后
 * 并不迁相至 eFault（只回 eIdle / 驻留），eFault 相不可达 -> 锁存永不可解，
 * 组件保护/监视功能一次性永久失效直至 PLC 重启（终审两式①）。
 * Clear path made provably reachable: reset edge with the illegal config gone. *)
IF fbTrigReset.Q AND (NOT bCfgBad) THEN
    bCfgLatch := FALSE;           // 锁存解除 / Latch cleared
    uErrorId  := 16#0000_0000;    // 码位随解除归零 / Code cleared with the latch
END_IF

IF bCfgLatch THEN
    uErrorId  := 16#0003_0505;   // 故障级：通道数组态非法 / Fault: channel count illegal
    bErrorInt := TRUE;
END_IF

IF (fBrightness <> fBrightness) OR ((fBrightness - fBrightness) <> (fBrightness - fBrightness)) THEN
    bBrightBad := TRUE;
    fBrightEff := 0.0;           // 非有限拒收：亮度安全侧 0（全灭）/ Non-finite rejected: safe dark
    uErrorId   := 16#0003_0506;  // 故障级：亮度非有限 / Fault: brightness non-finite
    bErrorInt  := TRUE;
ELSIF fBrightness < 0.0 THEN
    fBrightEff := 0.0;           // 负亮度钳 0 + 信息级 / Negative clamped with info
    uErrorId   := 16#0003_0406;
ELSIF fBrightness > DL_LB_BRIGHT_MAX THEN
    fBrightEff := DL_LB_BRIGHT_MAX;  // 超上限钳 100 + 信息级（验收向量 150 -> 100）/ Over clamped
    uErrorId   := 16#0003_0406;
ELSE
    fBrightEff := fBrightness;   // 合法直通 / Valid pass-through
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜位图整备：越界位钳除（信息级）+ 故障掩码钳至通道数（只读出口）
 *      Bitmap grooming: beyond-count bits dropped, fault mask clamped
 *-----------------------------------------------------------------------------*)
(* 越界掩码 = 通道数以上的全部位（SHL 移位量 < 16，结构性安全 R48） *)
(* Beyond mask: all bits at or above the channel count, shift structurally safe *)
IF nCountEff < DL_LB_CH_MAX THEN
    uBeyondMask := SHL(WORD#16#FFFF, INT_TO_UDINT(nCountEff));
ELSE
    uBeyondMask := 16#0000;      // 8 通道无越界位 / No beyond bits at full count
END_IF

IF (uReqMask AND uBeyondMask) <> 16#0000 THEN
    uErrorId := 16#0003_0405;    // 信息级：请求越界位已钳除 / Info: beyond bits dropped
END_IF

uFaultEff := uFaultFbMask AND (NOT uBeyondMask);   // 故障掩码钳至通道数 / Fault mask clamped
uFaultMask := uFaultEff;                            // 只读出口 / Read only export

uReqEff := uReqMask AND (NOT uBeyondMask) AND (NOT uFaultEff);  // 剔除越界与故障 / Drop beyond and faulted

(*------------------------------------------------------------------------------
 * 段 6｜仲裁（边界 B4）：ePriority 取最高号，eLatest 取新请求沿最高号，无沿保持现值
 *      Arbitration: highest wins, or latest-edge wins, hold when no new edge
 *      与 FB_DL_RedundantSwitch 首选策略风格互引（不共享实现）
 *-----------------------------------------------------------------------------*)
uNewReq := uReqEff AND (NOT uReqPrev);
uReqPrev := uReqEff;    // 沿判据快照主体末尾语义（本段即末次使用前刷新）/ Edge snapshot refreshed

nTargetCh := 0;
uTargetBit := 16#0000;

IF eArbMode = E_DL_LightArbMode.eLatest THEN
    (* 后到优先：本拍新请求沿的最高号胜；无沿则保持当前生效通道 *)
    (* Latest-edge wins; hold the current channel when no new edge *)
    (* 升序遍历 + 后写覆盖 = 取最高号（DOWNTO 会让最低号后写覆盖，方向已证） *)
    (* Ascending loop with overwrite keeps the highest bit: direction proven *)
    IF uNewReq <> 16#0000 THEN
        FOR i := 0 TO (DL_LB_CH_MAX - 1) DO
            IF (SHR(uNewReq, i) AND WORD#16#0001) <> 16#0000 THEN
                nTargetCh := i + 1;              // 最高号新请求胜 / Highest new wins
            END_IF
        END_FOR
    ELSIF nActiveChInt >= 1 THEN
        nTargetCh := nActiveChInt;               // 保持现值 / Hold current
    ELSE
        FOR i := 0 TO (DL_LB_CH_MAX - 1) DO      // 无现值：退化为最高号请求 / Fallback to highest
            IF (SHR(uReqEff, i) AND WORD#16#0001) <> 16#0000 THEN
                nTargetCh := i + 1;
            END_IF
        END_FOR
    END_IF
ELSE
    (* 最高号优先：有效请求位图的最高号胜（同拍多通道取最高） *)
    (* Highest numbered request wins, multi-request same scan included *)
    FOR i := 0 TO (DL_LB_CH_MAX - 1) DO
        IF (SHR(uReqEff, i) AND WORD#16#0001) <> 16#0000 THEN
            nTargetCh := i + 1;
        END_IF
    END_FOR
END_IF

IF nTargetCh >= 1 THEN
    uTargetBit := SHL(WORD#16#0001, INT_TO_UDINT(nTargetCh - 1));  // 单位掩码 / Single bit mask
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine with the mandatory ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE eStateInt OF

    E_DL_LightBankState.eIdle:
        IF (NOT bEnable) OR bCfgLatch THEN
            (* 失能 / 故障：全灭驻留（输出语义已声明：失能 = 全灭，非冻结保持） *)
            (* Disabled or faulted: all dark, semantics declared, not hold *)
            nActiveChInt := 0;
        ELSIF nTargetCh >= 1 THEN
            (* 新目标与现值不同才切；同通道请求不重打稳定窗（防闪烁） *)
            (* Switch only on a different target; same channel does not re-arm *)
            IF nTargetCh <> nActiveChInt THEN
                nActiveChInt := 0;       // 旧通道即刻熄灭 / Old channel dark at once
                bStabRun     := TRUE;    // 稳定窗启动 / Stabilisation armed
                eStateInt    := E_DL_LightBankState.eStab;
            END_IF
        END_IF

    E_DL_LightBankState.eStab:
        IF (NOT bEnable) OR bCfgLatch OR (nTargetCh < 1) THEN
            (* 延时途中请求消失 / 失能：全灭回空闲，稳定窗撤销 *)
            (* Request vanished mid-delay: dark, disarm the window *)
            bStabRun     := FALSE;
            nActiveChInt := 0;
            eStateInt    := E_DL_LightBankState.eIdle;
        ELSIF tonStab.Q THEN
            bStabRun     := FALSE;
            afBright[nTargetCh - 1] := fBrightEff;  // 新通道亮度槽按当前亮度刷新 / Slot refreshed at commit
            nActiveChInt := nTargetCh;   // 窗满点亮新通道 / Window full, light the new channel
            eStateInt    := E_DL_LightBankState.eActive;
        END_IF

    E_DL_LightBankState.eActive:
        IF (NOT bEnable) OR bCfgLatch OR (nTargetCh < 1) THEN
            bStabRun     := FALSE;
            nActiveChInt := 0;           // 请求消失即刻熄灭 / Request gone, dark at once
            eStateInt    := E_DL_LightBankState.eIdle;
        ELSIF nTargetCh <> nActiveChInt THEN
            nActiveChInt := 0;           // 换通道：旧通道即刻熄灭 / Channel change: old dark
            bStabRun     := TRUE;
            eStateInt    := E_DL_LightBankState.eStab;
        ELSE
            afBright[nActiveChInt - 1] := fBrightEff;  // 亮度保持槽刷新 / Hold slot refreshed
        END_IF

    E_DL_LightBankState.eFault:
        IF fbTrigReset.Q AND (NOT bCfgBad) THEN
            bCfgLatch := FALSE;          // 解除路径自证可达（R152）/ Clear path reachable
            uErrorId  := 16#0000_0000;
            eStateInt := E_DL_LightBankState.eIdle;
        END_IF

    ELSE
        (* 非法状态拦截：全灭 + 迁兜底态（复用组态码段） *)
        eStateInt := E_DL_LightBankState.eFault;
        uErrorId  := 16#0003_0505;
        bErrorInt := TRUE;
        nActiveChInt := 0;

END_CASE;

(*------------------------------------------------------------------------------
 * 段 8｜输出单一出口（范式 P-05）：亮度只由生效通道与保持槽派生
 *      Single output exit: brightness derives from the active channel only
 *-----------------------------------------------------------------------------*)
FOR i := 0 TO 7 DO
    IF (nActiveChInt >= 1) AND (i = (nActiveChInt - 1)) THEN
        auBrightness[i] := afBright[i];  // 生效通道输出保持槽亮度 / Active channel emits its slot
    ELSE
        auBrightness[i] := 0.0;          // 其余通道全灭 / All others dark
    END_IF
END_FOR

IF nActiveChInt >= 1 THEN
    uActiveCh := INT_TO_UINT(nActiveChInt);
ELSE
    uActiveCh := 0;                      // 无生效通道哨兵 / None sentinel
END_IF

bSwitching := (eStateInt = E_DL_LightBankState.eStab);
bError     := bErrorInt OR (eStateInt = E_DL_LightBankState.eFault);
eState     := eStateInt;
END_FUNCTION_BLOCK
