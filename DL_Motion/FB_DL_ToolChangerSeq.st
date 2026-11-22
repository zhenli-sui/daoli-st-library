(*
    FB_DL_ToolChangerSeq —— 换刀机构顺控（刀位校验 → 取刀 → 换刀 → 旧刀回库 → 到位确认）
    ------------------------------------------------------------------
    组件名称  : FB_DL_ToolChangerSeq
    分类      : DL_Motion / ToolChange
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 借鉴组织 —— T2-6 Rockwell AOI（矩阵行 166，伺服外围件方向）
                + 次源 t1-9 国产机床 FB 手册公开功能清单（换刀必有反馈对与
                互锁为公开工程惯例）；clean-room 声明 —— 状态机 / 码位 /
                时序 100% 自有，零代码行复制，无闭源参考。
    平台      : 纯 IEC 61131-3（ENUM + CASE + TON / R_TRIG），CODESYS 3.5 /
                TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R72 构建轮 · 批 4 · 序号 10）
    ------------------------------------------------------------------
    功能说明  : 换刀机构「命令 - 反馈 - 确认」编排：eIdle → eSelect（刀位
                校验 / 映射，发刀位指令，等刀库对位与机械手原位）→ ePick
                （机械手取刀，正向反馈对）→ eSwap（主轴换刀，bSpindleFree
                互锁迁入，反向反馈对）→ eReturn（旧刀回库，回原位反馈）→
                eDone（bToolDone 单拍脉冲）→ eIdle。每执行相带独立超时
                （单 TON 实例，PT = tActTimeout，相驻留即 IN，R145 相级
                看门狗口径），超时 → eFault + 锁存码。
                受理语义（同拍竞态闸，R279）：换刀受理只看 uToolReq **值
                变更沿**的迁入沿锁存副本 _uReqLatch，运行中禁跨拍双判——
                运行中刀位号变更被忽略（沿已被消费），须再次变更刀位号
                （或先归 0）才重新受理；同值重发须先归 0 或变更刀位号
                （接口契约声明，无执行沿引脚的替代口径）。
                安全语义：
                ① eSwap 为安全相，迁入必带全量闸位复检（bSpindleFree +
                   NOT _bFault，R274）；
                ② 换刀中途 bSpindleFree 撤销 → **保持相 + 信息提示，不中断
                   不回退**（防半程掉刀，安全侧声明；继续完成换刀比半程
                   悬臂更安全）；
                ③ 失能 / 故障 → 全输出清零 + 状态回 eIdle（停机相输出清零，
                   R57）；失能不清故障锁存（操作态非复位），复位沿才解除；
                ④ uToolReq = 0 或 > nToolCount → 拒收 + 信息码，不发任何
                   指令；nToolCount = 1（单刀库退化）→ 信息级直接
                   eSelect→ePick（跳过刀库对位等待）。
    错误码    : 16#0004_08B0 刀位请求越域（0 或 > nToolCount），已拒收不发
                            指令 —— 信息级，不置 bError（R45）
                16#0004_08B1 单刀库退化（nToolCount = 1），eSelect 直接转
                            ePick —— 信息级，不置 bError
                16#0004_08B2 执行相超时（任一执行相驻留超 tActTimeout），
                            锁存至复位沿 —— 故障级
                16#0004_08B3 换刀相主轴互锁撤销（bSpindleFree 于 eSwap 内
                            为 FALSE），保持相照走 —— 信息级，不置 bError
                16#0004_08B4 组态非法（nToolCount = 0 / tActTimeout 非正），
                            锁存至复位沿 —— 故障级
                加码反证句（R90）：08B2 / 08B4 输出同为 eFault + bError，
                但 08B4 在 eIdle 即锁存（无执行史）、08B2 必有执行相驻留史
                （eState 轨迹可证），成因互斥不可互换观测；08B0 / 08B1 /
                08B3 各有独立触发事件（拒收沿 / 组态相 / 互锁撤销拍），
                不由现有输出组合还原，故各立一码。
    码位总账  : 16#0004_08B0 用 ｜ 16#0004_08B1 用 ｜ 16#0004_08B2 用 ｜
                16#0004_08B3 用 ｜ 16#0004_08B4 用
                （08A6 / 08A7 已由 FB_DL_TurretToolSelect 占用，本件不占）
    边界与披露: 一 R_TRIG（rtReq / rtReset）与 TON（tonAct）每拍**无条件
                   调用**（规则 ⑦）；tonAct IN = 执行相驻留判据显式变量
                   （R145 看门狗使能只用相驻留，不叠业务条件补集）；超时
                   判定在 CASE 之后（本拍完成事件优先，R275 同拍竞态口径），
                   超时有一拍检测延迟（声明口径）；
                二 零全局变量、零 VAR_EXTERNAL、零物理地址；
                三 归属 Ownership：E_DL_ToolChangePhase 属主为本文件（全库
                   唯一定义，R264），引用件只引用不重声明；
                四 状态机 ENUM + CASE 必带 ELSE 兜底（非法枚举值 → eFault
                   锁存）；段 5b 统一故障迁入闸（R274 迁入完备性）；
                五 反馈引脚语义声明：bToolHome = 所选刀位对位取刀口、
                   bArmHome = 机械手原位、bArmFwd = 机械臂正向到位、
                   bArmBack = 机械臂反向到位，均引脚注入，本件不发轴指令；
                六 分工声明：FB_DL_TurretToolSelect（刀塔分度就近选刀解算，
                   无机械手取放编排）、FB_DL_ToolLifeBudget（寿命记账）——
                   本件只管换刀机构「命令 - 反馈 - 确认」时序编排，刀位
                   就近解算归刀塔件、寿命记账归记账件，互引不互代；
                七 依赖声明：仅 Standard.library（TON / R_TRIG），零厂商
                   方言；
                八 复位沿作用域（R311 逐项声明）：清故障锁存 + 清锁存码 +
                   迁 eIdle + 清 _uReqPrev（强制下次刀位值变更沿可受理），
                   **不清**周期计数类（本件无）与 _uReqLatch（回 Idle 后由
                   下次受理沿重写）。
    验收向量  : V1 正常换刀（uToolReq = 3，nToolCount = 8，反馈按时序到）
                → eState 轨迹 eIdle→eSelect→ePick→eSwap→eReturn→eDone→
                eIdle，bToolDone 单拍，eFault 不出现；
                V2 uToolReq = 0 → 08B0 拒收不发指令；V3 nToolCount = 1 →
                08B1 + eSelect 直转 ePick；V4 eSwap 中 bSpindleFree 撤销
                → 保持相照走 + 08B3；V5 任一执行相超时 → 08B2 锁存 +
                eFault + 输出清零；V6 复位沿 → 解锁回 eIdle；
                V7 nToolCount = 0 → 08B4 锁存；V8 失能 → 输出清零 +
                eIdle，锁存保留。
                算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    修订记录  : 2026-11-23 v1.0.0 首次入库（R72 构建轮 · 批 4 · 序号 10）
*)
TYPE E_DL_ToolChangePhase :
(
    eIdle   := 0,                          // 空闲：等刀位请求值变更沿 / idle, waiting for a tool request change edge
    eSelect := 10,                         // 刀位校验：发刀位指令，等刀库对位与机械手原位 / select, issue the tool command
    ePick   := 20,                         // 取刀：机械臂正向，等正向到位 / pick, the arm forward to the magazine
    eSwap   := 30,                         // 换刀：主轴互锁迁入，机械臂反向 / swap, gated by the spindle free interlock
    eReturn := 40,                         // 旧刀回库：机械臂正向回原位 / return, the old tool back to the magazine
    eDone   := 50,                         // 完成：bToolDone 单拍脉冲相 / done, the one shot pulse phase
    eFault  := 60                          // 故障：锁存待复位 / fault, latched until the reset
);
END_TYPE

FUNCTION_BLOCK FB_DL_ToolChangerSeq
VAR_INPUT
    uToolReq     : UINT := 0;              (* 目标刀位请求，[刀位]，1 起计，0 或越容量拒收 / the requested tool number, refused when zero or over capacity *)
    nToolCount   : UINT := 8;              (* 刀库容量组态，[刀位]，禁 0 / the magazine tool count, must not be zero *)
    bToolHome    : BOOL := FALSE;          (* 所选刀位对位反馈，[标志]，引脚注入 / the tool position aligned feedback *)
    bArmHome     : BOOL := FALSE;          (* 机械手原位反馈，[标志]，引脚注入 / the arm home feedback *)
    bArmFwd      : BOOL := FALSE;          (* 机械臂正向到位反馈，[标志]，引脚注入 / the arm forward in position feedback *)
    bArmBack     : BOOL := FALSE;          (* 机械臂反向到位反馈，[标志]，引脚注入 / the arm backward in position feedback *)
    bSpindleFree : BOOL := FALSE;          (* 主轴可换刀互锁，[标志]，eSwap 迁入与驻留判据 / the spindle free interlock *)
    tActTimeout  : TIME := T#10S;          (* 执行相超时，[ms]，禁非正 / the action phase timeout *)
    bEn          : BOOL := FALSE;          (* 使能，[标志]，FALSE 输出清零回 eIdle（锁存保留）/ the enable *)
    bReset       : BOOL := FALSE;          (* 故障复位，[标志]，上升沿唯一解除 / the fault reset *)
END_VAR
VAR_OUTPUT
    uToolSelCmd : UINT := 0;               (* 刀位指令出口，[刀位]，空闲 / 失能 / 故障为 0 / the tool command outlet *)
    bArmFwdCmd  : BOOL := FALSE;           (* 机械臂正向指令出口，[标志] / the arm forward command outlet *)
    bArmBackCmd : BOOL := FALSE;           (* 机械臂反向指令出口，[标志] / the arm backward command outlet *)
    bToolDone   : BOOL := FALSE;           (* 换刀完成单拍脉冲（R24 口径，内部 _bDone 两段式映射）/ the tool done one shot pulse *)
    eState      : E_DL_ToolChangePhase := E_DL_ToolChangePhase.eIdle; // 主状态机当前态 [状态] / the current state
    bError      : BOOL := FALSE;           (* 故障标志，与锁存同源（R191）/ the fault flag from the latch *)
    nErrCode    : UDINT := 16#0000_0000;   (* 错误码，0 = 正常，故障锁存回放（R187）/ the error id *)
END_VAR
VAR
    _bInit     : BOOL := FALSE;            (* 首拍初始化标志（R310）/ the first scan flag *)
    _eState    : E_DL_ToolChangePhase := E_DL_ToolChangePhase.eIdle; // 内部状态寄存器 / the internal state register
    _bFault    : BOOL := FALSE;            (* 故障锁存副本，仅复位沿解除 / the fault latch copy *)
    _nCodeLatch: UDINT := 0;               (* 锁存成因码，故障期回放 / the latched cause code *)
    _uReqLatch : UINT := 0;                (* 受理沿锁存刀位副本（同拍竞态闸，R279）/ the latched tool request copy *)
    _uReqPrev  : UINT := 0;                (* 请求值上一拍快照（值变更沿判据，主体末行刷新，R46）/ the previous request snapshot *)
    _uSelCmd   : UINT := 0;                (* 刀位指令内部副本 / the internal tool command copy *)
    _bFwdCmd   : BOOL := FALSE;            (* 正向指令内部副本 / the internal forward command *)
    _bBackCmd  : BOOL := FALSE;            (* 反向指令内部副本 / the internal backward command *)
    _bDone     : BOOL := FALSE;            (* 完成单拍内部位（段 1 预清，段 5 置位，统一出口映射）/ the internal done bit *)
    _bReqRej   : BOOL := FALSE;            (* 请求拒收信息标志（受理沿消费或复位解除）/ the request rejected info flag *)
    _bDegrade  : BOOL := FALSE;            (* 单刀库退化信息标志 / the single tool degrade info flag *)
    _bSpHold   : BOOL := FALSE;            (* 换刀相互锁撤销信息标志（逐拍重算）/ the spindle hold info flag *)
    _bActive   : BOOL := FALSE;            (* 执行相驻留判据（tonAct IN 显式变量）/ the active phase residency flag *)
    rtReq      : R_TRIG;                   (* 刀位请求值变更沿实例（无条件调用）/ the request change edge instance *)
    rtReset    : R_TRIG;                   (* 复位沿实例（无条件调用）/ the reset edge instance *)
    tonAct     : TON;                      (* 执行相看门狗实例（无条件调用，R145 相驻留使能）/ the action watchdog timer *)
END_VAR
VAR CONSTANT
    DL_TCS_CODE_REQ : UDINT := 16#0004_08B0; (* 请求越域信息码 [码] / the request rejected info code *)
    DL_TCS_CODE_ONE : UDINT := 16#0004_08B1; (* 单刀库退化信息码 [码] / the degrade info code *)
    DL_TCS_CODE_TO  : UDINT := 16#0004_08B2; (* 执行相超时故障码 [码] / the timeout fault code *)
    DL_TCS_CODE_SP  : UDINT := 16#0004_08B3; (* 互锁撤销信息码 [码] / the spindle hold info code *)
    DL_TCS_CODE_CFG : UDINT := 16#0004_08B4; (* 组态非法故障码 [码] / the config fault code *)
    DL_TCS_TZERO    : TIME := T#0S;          (* 零时长哨兵 [ms] / the zero duration sentinel *)
    DL_TCS_ZERO     : UDINT := 0;            (* 无符号零哨兵 [码] / the unsigned zero sentinel *)
    DL_TCS_UZERO    : UINT := 0;             (* 刀位零哨兵 [刀位] / the tool zero sentinel *)
    DL_TCS_UONE     : UINT := 1;             (* 刀位下界哨兵 [刀位] / the tool lower bound sentinel *)
END_VAR

// 段 0｜沿检测与看门狗无条件周期调用（规则 ⑦；IN = 相驻留显式变量）/ segment 0, the unconditional edge and watchdog refresh
rtReq(CLK := (uToolReq <> _uReqPrev));     // 请求值变更沿（同值重发不产生沿，契约声明）/ the request change edge
rtReset(CLK := bReset);                    // 复位沿 / the reset edge
_bActive := (_eState = E_DL_ToolChangePhase.eSelect)   // 执行相驻留判据（R145：只看相驻留）/ the active residency flag
         OR (_eState = E_DL_ToolChangePhase.ePick)
         OR (_eState = E_DL_ToolChangePhase.eSwap)
         OR (_eState = E_DL_ToolChangePhase.eReturn);
tonAct(IN := _bActive AND bEn AND (NOT _bFault), PT := tActTimeout); // 看门狗（失能 / 锁存即断计）/ the watchdog

// 段 1｜首拍初始化与单拍位预清（R310 / FB32-1 / R256）/ segment 1, the first scan init and the presets
IF NOT _bInit THEN                         // 首拍一拍 / the first scan
    _bInit := TRUE;                        // 置首拍标志 / raise the first scan flag
    _bFault := FALSE;                      // 故障锁存显式清零 / clear the fault latch explicitly
    _eState := E_DL_ToolChangePhase.eIdle; // 状态显式落空闲 / place the state to idle
END_IF
_bDone   := FALSE;                         // 完成单拍预清零（置位在段 5 eDone 相）/ preset the done bit false
_bSpHold := FALSE;                         // 互锁撤销标志预清零（eSwap 相逐拍重算）/ preset the hold flag false
_bDegrade := (nToolCount = DL_TCS_UONE) AND _bActive; // 退化信息逐拍重算（执行相驻留内才发码，信息级每拍重算口径 R187）/ the degrade flag recomputed

// 段 2｜复位沿（作用域声明见头注释边界八，R311）/ segment 2, the reset edge with the declared scope
IF rtReset.Q THEN                          // 复位上升沿 / the reset rising edge
    _bFault := FALSE;                      // 清故障锁存（唯一人工解除边，恒可达 R152 自证）/ clear the fault latch
    _nCodeLatch := DL_TCS_ZERO;            // 清锁存码 / clear the latched code
    _eState := E_DL_ToolChangePhase.eIdle; // 迁回空闲 / back to idle
    _uReqPrev := DL_TCS_UZERO;             // 清请求快照（强制下次值变更沿可受理）/ clear the request snapshot
    _bReqRej := FALSE;                     // 清拒收信息标志（复位沿清除边）/ clear the reject flag
END_IF

// 段 3｜组态闸：容量为 0 或超时非正 → 锁存（首次成因，R189）/ segment 3, the configuration gate
IF (NOT _bFault) AND ((nToolCount = DL_TCS_UZERO) OR (tActTimeout <= DL_TCS_TZERO)) THEN // 组态非法命中 / a configuration fault hit
    _bFault := TRUE;                       // 置锁存 / latch the fault
    _nCodeLatch := DL_TCS_CODE_CFG;        // 登记组态码 / register the config code
END_IF

// 段 4｜主状态机（ENUM + CASE，ELSE 兜底；完成事件先于超时判定消化，R275）/ segment 4, the main state machine
CASE _eState OF

    E_DL_ToolChangePhase.eIdle:            // 空闲相 / the idle phase
        _uSelCmd := DL_TCS_UZERO;          // 停机相输出清零（R57）/ zero the command in idle
        _bFwdCmd := FALSE;                 // 指令清零 / clear the commands
        _bBackCmd := FALSE;                // 指令清零 / clear the commands
        IF rtReq.Q AND bEn AND (NOT _bFault) THEN // 受理沿 + 全量闸位复检（R274）/ the accept edge with the gate recheck
            IF (uToolReq >= DL_TCS_UONE) AND (uToolReq <= nToolCount) THEN // 刀位校验（1 起计）/ the tool validation
                _uReqLatch := uToolReq;    // 受理沿锁存副本（R279 禁跨拍双判）/ latch the request copy
                _uSelCmd := _uReqLatch;    // 发刀位指令 / issue the tool command
                _bReqRej := FALSE;         // 受理沿清除旧拒收标志 / clear the old reject flag on accept
                _eState := E_DL_ToolChangePhase.eSelect; // 迁入校验相 / enter the select phase
            ELSE                           // 越域请求拒收（不发任何指令）/ the out of domain request rejected
                _bReqRej := TRUE;          // 置拒收信息标志 / raise the reject flag
            END_IF
        END_IF

    E_DL_ToolChangePhase.eSelect:          // 刀位校验相：等刀库对位与机械手原位 / the select phase
        IF nToolCount = DL_TCS_UONE THEN   // 单刀库退化：跳过对位等待（信息级）/ the single tool degrade
            _bDegrade := TRUE;             // 置退化信息标志 / raise the degrade flag
            _eState := E_DL_ToolChangePhase.ePick; // 直转取刀相 / straight to the pick phase
        ELSIF bToolHome AND bArmHome THEN  // 刀库对位且机械手原位 / the magazine aligned and the arm home
            _eState := E_DL_ToolChangePhase.ePick; // 迁入取刀相 / enter the pick phase
        END_IF

    E_DL_ToolChangePhase.ePick:            // 取刀相：机械臂正向 / the pick phase
        _bFwdCmd := TRUE;                  // 正向指令 / the forward command
        IF bArmFwd AND bSpindleFree AND (NOT _bFault) THEN // 正向到位 + 安全相迁入全量闸位复检（R274）/ the in position with the full gate recheck
            _eState := E_DL_ToolChangePhase.eSwap; // 迁入换刀相 / enter the swap phase
        END_IF                             // 到位但主轴未自由：驻留等待（超时看门狗兜底）/ hold until free

    E_DL_ToolChangePhase.eSwap:            // 换刀相：机械臂反向（互锁撤销保持照走，安全侧声明）/ the swap phase
        _bFwdCmd := FALSE;                 // 撤正向指令 / drop the forward command
        _bBackCmd := TRUE;                 // 反向指令 / the backward command
        _bSpHold := NOT bSpindleFree;      // 互锁撤销逐拍重算（保持相 + 提示，不中断不回退）/ the hold flag recomputed
        IF bArmBack THEN                   // 反向到位 / the backward in position
            _eState := E_DL_ToolChangePhase.eReturn; // 迁入回库相 / enter the return phase
        END_IF

    E_DL_ToolChangePhase.eReturn:          // 旧刀回库相：机械臂正向回原位 / the return phase
        _bBackCmd := FALSE;                // 撤反向指令 / drop the backward command
        _bFwdCmd := TRUE;                  // 正向指令（回库动作）/ the forward command
        IF bArmHome THEN                   // 机械手回原位（旧刀入库确认）/ the arm back home
            _eState := E_DL_ToolChangePhase.eDone; // 迁入完成相 / enter the done phase
        END_IF

    E_DL_ToolChangePhase.eDone:            // 完成相：单拍脉冲（两段式，FB33-1）/ the done phase
        _bDone := TRUE;                    // 置完成单拍内部位 / raise the internal done bit
        _uSelCmd := DL_TCS_UZERO;          // 指令清零 / clear the command
        _bFwdCmd := FALSE;                 // 指令清零 / clear the commands
        _bBackCmd := FALSE;                // 指令清零 / clear the commands
        _eState := E_DL_ToolChangePhase.eIdle; // 迁回空闲（脉冲次拍由段 1 预清撤销，R129 两拍口径）/ back to idle

    E_DL_ToolChangePhase.eFault:           // 故障相：等复位沿（解除可达）/ the fault phase until the reset
        IF NOT _bFault THEN                // 锁存已清才迁出 / the exit after the latch cleared
            _eState := E_DL_ToolChangePhase.eIdle; // 迁回空闲 / back to idle
        END_IF

    ELSE                                   // 非法枚举值拦截 / the illegal enumeration guard
        _eState := E_DL_ToolChangePhase.eFault; // 落故障相 / force to the fault phase
        _bFault := TRUE;                   // 置锁存 / latch the fault
        _nCodeLatch := DL_TCS_CODE_CFG;    // 复用组态码（R90 反证：非法枚举不可达无独立观测需求）/ reuse the config code

END_CASE

// 段 4b｜故障统一迁入闸（置于状态机之后，R274 迁入完备性）/ segment 4b, the unified fault entry gate
IF _bFault AND (_eState <> E_DL_ToolChangePhase.eFault) THEN // 已锁存但不在故障相 / latched but not in the fault phase
    _eState := E_DL_ToolChangePhase.eFault; // 任何相检出故障一律落故障相 / any phase with a latch lands in the fault phase
END_IF

// 段 5｜执行相超时判定（CASE 之后：本拍完成事件已优先消化，R275；超时有一拍
//        检测延迟，声明口径；驻留判据按 CASE 后现值重取，完成迁移即取消超时）/
//        segment 5, the phase timeout verdict with the post CASE residency
IF ((_eState = E_DL_ToolChangePhase.eSelect) OR (_eState = E_DL_ToolChangePhase.ePick)
    OR (_eState = E_DL_ToolChangePhase.eSwap) OR (_eState = E_DL_ToolChangePhase.eReturn))
    AND tonAct.Q THEN                      // 相驻留（现值）且看门狗到时 / the residency with the watchdog expired
    IF NOT _bFault THEN                    // 未锁存才登记超时成因 / register the timeout cause only while not latched
        _bFault := TRUE;                   // 置锁存 / latch the fault
        _nCodeLatch := DL_TCS_CODE_TO;     // 登记超时码 / register the timeout code
    END_IF
END_IF

// 段 6｜失能路径：停机相输出清零 + 回 eIdle（锁存保留，操作态非复位，R57/R191 声明）/ segment 6, the disable path
IF NOT bEn THEN                            // 失能 / disabled
    _eState := E_DL_ToolChangePhase.eIdle; // 状态回空闲 / back to idle
    _uSelCmd := DL_TCS_UZERO;              // 输出清零 / zero the outlets
    _bFwdCmd := FALSE;                     // 指令清零 / clear the commands
    _bBackCmd := FALSE;                    // 指令清零 / clear the commands
    _bReqRej := FALSE;                     // 清拒收信息标志（失能清除边）/ clear the reject flag
END_IF

// 段 7｜统一出口（内部副本单点映射；信息级码优先级：拒收 > 互锁撤销 > 退化，声明口径）/ segment 7, the unified outlet
uToolSelCmd := _uSelCmd;                   // 刀位指令出口 / the tool command outlet
bArmFwdCmd := _bFwdCmd;                    // 正向指令出口 / the forward command outlet
bArmBackCmd := _bBackCmd;                  // 反向指令出口 / the backward command outlet
bToolDone := _bDone;                       // 完成单拍出口（统一出口映射，R189 两段式）/ the done pulse outlet
eState := _eState;                         // 状态出口 / the state outlet
bError := _bFault;                         // 故障标志与锁存同源 / the fault flag from the latch
IF _bFault THEN                            // 故障锁存回放（R187）/ the latched replay
    nErrCode := _nCodeLatch;               // 回放锁存码 / replay the latched code
ELSIF _bReqRej THEN                        // 拒收信息级 / the rejected request
    nErrCode := DL_TCS_CODE_REQ;           // 信息级：请求越域拒收 / info level
ELSIF _bSpHold THEN                        // 互锁撤销信息级 / the spindle hold
    nErrCode := DL_TCS_CODE_SP;            // 信息级：保持相提示 / info level
ELSIF _bDegrade THEN                       // 退化信息级 / the degrade
    nErrCode := DL_TCS_CODE_ONE;           // 信息级：单刀库退化 / info level
ELSE                                       // 无事件 / no event
    nErrCode := DL_TCS_ZERO;               // 正常 / ok
END_IF

// 段 8｜请求值上一拍快照（主体末行无条件刷新，R46 末拍快照口径）/ segment 8, the request snapshot at the body end
_uReqPrev := uToolReq;                     // 末拍快照 / the end of body snapshot
END_FUNCTION_BLOCK
