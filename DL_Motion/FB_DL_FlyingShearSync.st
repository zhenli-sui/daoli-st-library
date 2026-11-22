(*
    FB_DL_FlyingShearSync —— 飞剪同步控制器（加速进入 → 线速同步跟踪 → 剪切触发 → 减速退出）
    ------------------------------------------------------------------
    组件名称  : FB_DL_FlyingShearSync
    分类      : DL_Motion / Synchronization
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 借鉴点 —— PLCopen 对「飞剪 / 飞锯属同步应用」的公开分类事实，
                以及「同步窗 + 速度匹配」的参数域组织方式。
                本件只借**分类事实与参数域组织**，同步区插补数学 / 状态机 /
                码位 100% clean-room 自有，不自造轴状态枚举（轴状态归运动层，
                R31 家族高危区纪律），不引用任何轴接口。
                clean-room 声明 —— 零代码行复制；定时与沿检测仅用 IEC 61131-3
                标准库 TON / R_TRIG，数学仅用标准运算符与 ABS / MAX。
                许可证 —— 本件 MIT；来源标签 t1-6-plcopen 仅指规范文档公开语义，
                规范文本不属代码，无许可继承关系。
    平台      : 纯 IEC 61131-3，CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R71 构建轮 · 批 2 · 序号 5）
    ------------------------------------------------------------------
    功能说明  : 速度级飞剪四段顺控（本件出口为**刀轴速度指令**，非位置指令）：
                eIdle 待机（刀速 0，等切剪请求上升沿）→ eAccel 斜坡加速
                （以 fAccel 向产品线速 fProductVel 逼近，速度差进入 fSyncTol
                即转同步）→ eSyncTrack 线速同步跟踪（刀速直接跟随线速，刀行
                进积分位置进入同步窗 [fShearLen - fSyncWinLen, fShearLen] 后
                受理切剪）→ eCutFire 剪切触发（单拍脉冲，R24 / R187 口径：
                内部 _bCutPulse 置位 → 段 10 统一出口映射单拍，次拍段 1 清零）
                → eDecel 斜坡退窗（以 fDecel 归零）→ eIdle。
                切剪受理规则（计划口径）：bCutReq 上升沿在 eIdle 启动周期并
                预武装 _bCutArmed；在 eSyncTrack 到达即受理（更新武装）；在
                eAccel / eCutFire / eDecel 到达即拒收并计数（信息级，不排队）。
                窗满未剪：eSyncTrack 中刀行进越过 fShearLen 仍未触发 → 信息级
                跳过、撤销武装、强制进 eDecel 清窗（同拍竞态闸：bCutReq 受理
                与窗满判定在同一 CASE 拍内完成，禁跨拍双判）。
                斜坡积分口径（R38）：每拍增量 = 加 / 减速度 × 扫描周期
                （tCycle 引脚注入，无魔法数），运算基于上一拍锁存副本
                _fKnifeCmd，出口单点映射（R191 名实双出口）。
                超时监控（R40）：单实例 _tonPhase，PT 由当前相逐相选择
                （eAccel → tAccelMax，eSyncTrack → tSyncMax，eDecel →
                tDecelMax，段 8 无条件调用），相切换时 IN 随条件清零复位，
                **不跨相累计**（定时器纪律：单定时器逐相 PT，已声明选型）。
                失能语义（R57 / R303）：bEn = FALSE → 速度指令**单拍安全归零**
                （不走斜坡：本件出口为速度指令，斜坡语义由驱动器自身承担，
                停机相输出清零优先于斜坡，安全侧不延时）、状态回 eIdle、
                剪切输出清零；锁存故障不被失能清除，仅 bReset 上升沿解除。
    错误码    : 16#0002_3790 组态非法（切长 / 窗长非正、切长 < 窗长、加速度 /
                            减速度 / 容差非正、扫描周期 / 超时非正、任一非有限），
                            锁存 —— 故障级
                16#0002_3791 加速相超时（未能匹配线速），锁存 —— 故障级
                16#0002_3792 减速相超时（未能归零），锁存 —— 故障级
                16#0002_3793 非法相枚举（CASE ELSE 兜底），锁存 —— 故障级
                16#0002_3798 同步跟踪相超时（窗积分停滞 / 迟迟未到窗），锁存
                            —— 故障级
                16#0002_3794 同步窗满未触发剪切（窗内无有效受理请求），本次跳过
                            进减速 —— 信息级，不置 bError
                16#0002_3795 切剪请求被拒收（非受理相到达），已计数 —— 信息级，
                            不置 bError
                16#0002_3796 产品线速无效（非有限 / 负值），待机相拒收不启动
                            —— 信息级，不置 bError
                16#0002_3797 周期中产品线速失效（非有限 / 负值），锁存停机
                            —— 故障级
    码位总账  : 3790 / 3791 / 3792 / 3793 / 3797 / 3798 用（均故障级）
                3794 / 3795 / 3796 用（信息级，bError 恒 FALSE）
    状态机    : ENUM E_DL_FssPhase 六态，CASE 全覆盖 + ELSE 兜底（锁存 3793
                回 eFault）。迁移表见功能说明；bReset 上升沿：解锁存 →
                eIdle 并清刀速 / 刀位 / 武装（唯一可到达的解除边，R188）。
    边界与披露: 一 组态判据逐项点名（R272）：fShearLen / fSyncWinLen / fAccel /
                   fDecel / fSyncTol 五个 LREAL 全部纳入非有限闸；fSyncWinLen
                   <= 0、fShearLen <= 0、fShearLen < fSyncWinLen（同步窗长于
                   切长即无加速段可言）拦截；fAccel <= 0 / fDecel <= 0 /
                   fSyncTol <= 0 拦截；tCycle / tAccelMax / tDecelMax 非正拦截；
                二 线速守卫：fProductVel 非有限或 < 0.0，待机相拒收（3796，
                   不启动不发指令）；周期中失效锁存（3797，指令归零安全相）；
                   线速 = 0 合法（产品静止，刀速同步为 0，窗积分停滞，由超时
                   收口，头注释声明该边界行为）；
                三 失能相输出清零（R57）：fKnifeVelCmd / bCutTrig 全清零 +
                   状态回 eIdle；锁存相同样清零（失效 / 故障相回夹执行输出）；
                四 剪切脉冲为单拍（R24 / R187 两段式：CASE 内只写内部
                   _bCutPulse，段 10 统一出口映射，段 1 预清零收尾）；
                五 同拍双窗配比约束（R100）：无内建双窗，tAccelMax / tDecelMax
                   与 tCycle 的配比约束为「超时值 >= 2 × tCycle」，否则超时
                   判据可能在相驻留不足两拍时误触发 —— 由组态闸以
                   tAccelMax < 2 * tCycle 拦截（3790）；
                六 定时器 _tonPhase 与沿实例 _rtCut / _rtReset 均无条件周期调用；
                七 计数器 uCutRejCnt 饱和不回绕（增量前预判，R28-3 口径）；
                八 零全局变量、零 VAR_EXTERNAL、零物理地址、零数组下标。
    分工声明  : FB_DL_FlyingCutSync（R37，DL_Motion 同族最近邻）为**位置取模**
                切窗判据件：消费主轴位置、按切长取模计算相位、窗内判同步
                误差后发下刀脉冲，不带加 / 减速斜坡与速度指令出口；本件为
                **速度指令级**四段顺控件：消费产品线速、输出刀轴速度指令，
                两者入口 / 出口契约不同，互引分工不互代（本件立项时按
                R327 词根邻件扫描补记此边界）。FB_DL_LabelApplySync（贴标
                同步）、FB_DL_RotaryIndexModulo（分度回转）为其余同族邻件。
    修订记录  : 2026-11-22 v1.0.0 首次入库（R71 构建轮 · 批 2 · 序号 5）
*)
TYPE E_DL_FssPhase :
(
    eIdle      := 0,   (* 待机，刀速 0，等切剪请求上升沿 / idle, knife at zero, waiting for a cut request edge *)
    eAccel     := 10,  (* 斜坡加速相（向产品线速逼近）/ the accel phase, ramping toward the product speed *)
    eSyncTrack := 20,  (* 线速同步跟踪相（速度跟随 + 刀行进积分 + 同步窗判定）/ the sync track phase, speed follow plus travel integration plus window verdict *)
    eCutFire   := 30,  (* 剪切触发相（单拍脉冲，驻留一拍）/ the cut fire phase, a one scan single pulse *)
    eDecel     := 40,  (* 斜坡减速相（退窗归零）/ the decel phase, ramping back to zero *)
    eFault     := 50   (* 故障相（锁存待复位）/ the fault phase, latched for a reset *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_FlyingShearSync
VAR_INPUT
    bEn         : BOOL := TRUE;            (* 使能，[标志]，FALSE 时指令单拍归零并回待机（R57）/ the enable, FALSE zeroes the command at once and returns to idle *)
    bReset      : BOOL := FALSE;           (* 故障复位（上升沿有效），[标志] / the fault reset, rising edge effective *)
    bCutReq     : BOOL := FALSE;           (* 切剪请求（上升沿启动 / 受理），[标志] / the cut request, rising edge starts or is accepted *)
    fProductVel : LREAL := 0.0;            (* 产品线速，[mm/s]，须 >= 0.0，非有限拒收 / the product line speed, must be non negative and finite *)
    fShearLen   : LREAL := 1000.0;         (* 切长（刀行进目标里程），[mm]，须 >= fSyncWinLen / the shear length, the knife travel target *)
    fSyncWinLen : LREAL := 50.0;           (* 同步窗长（切长尾段允许剪切窗口），[mm]，须 > 0 且 <= fShearLen / the sync window length *)
    fAccel      : LREAL := 5000.0;         (* 加速度，[mm/s²]，须 > 0 / the acceleration *)
    fDecel      : LREAL := 5000.0;         (* 减速度，[mm/s²]，须 > 0 / the deceleration *)
    fSyncTol    : LREAL := 5.0;            (* 速度匹配容差，[mm/s]，须 > 0 / the speed match tolerance *)
    tCycle      : TIME := T#10MS;          (* 扫描周期，[ms]，须 > 0（斜坡积分基值）/ the scan cycle, the ramp integration base *)
    tAccelMax   : TIME := T#5S;            (* 加速相超时，[ms]，须 >= 2 * tCycle / the accel phase timeout *)
    tSyncMax    : TIME := T#10S;           (* 同步跟踪相超时，[ms]，须 >= 2 * tCycle（窗积分停滞的收口）/ the sync track phase timeout *)
    tDecelMax   : TIME := T#5S;            (* 减速相超时，[ms]，须 >= 2 * tCycle / the decel phase timeout *)
END_VAR
VAR_OUTPUT
    eState      : E_DL_FssPhase := E_DL_FssPhase.eIdle; (* 相状态出口，[相] / the phase outlet *)
    fKnifeVelCmd: LREAL;                   (* 刀轴速度指令，[mm/s]，恒 >= 0 / the knife axis velocity command, always non negative *)
    bCutTrig    : BOOL;                    (* 剪切触发脉冲（单拍），[标志] / the cut trigger pulse, single scan *)
    uCutRejCnt  : UDINT;                   (* 切剪请求拒收计数（饱和不回绕）/ the rejected cut request counter, saturating *)
    bValid      : BOOL;                    (* 出口可信（非锁存故障相），[标志] / the outlets trustworthy *)
    bError      : BOOL;                    (* 故障标志，锁存故障时为 TRUE / the fault flag, raised while latched *)
    nErrCode    : UDINT;                   (* 错误码，0 = 正常，锁存回放 / the error id, 0 = ok, replayed from the latch *)
END_VAR
VAR
    _rtCut      : R_TRIG;                  (* 切剪请求上升沿实例（无条件调用）/ the cut request rising edge instance *)
    _rtReset    : R_TRIG;                  (* 复位上升沿实例（无条件调用）/ the reset rising edge instance *)
    _tonPhase   : TON;                     (* 相超时计时实例（单定时器逐相 PT，无条件调用）/ the phase timeout timer, per phase PT *)
    _ePhase     : E_DL_FssPhase := E_DL_FssPhase.eIdle; (* 相状态寄存器 / the internal phase register *)
    _bFault     : BOOL;                    (* 故障锁存位，仅 bReset 上升沿解除 / the latched fault bit *)
    _nCodeLatch : UDINT;                   (* 锁存成因码，故障期回放 / the latched cause code, replayed *)
    _bCfgBad    : BOOL;                    (* 组态非法标志（逐拍重算）/ the configuration fault flag *)
    _bVelBad    : BOOL;                    (* 线速无效标志（逐拍重算）/ the velocity fault flag *)
    _bCutArmed  : BOOL;                    (* 切剪武装位（请求已受理待窗内触发）/ the cut armed flag, a request accepted and waiting for the window *)
    _bCutPulse  : BOOL;                    (* 剪切脉冲内部位（段 10 统一映射，R187）/ the internal cut pulse bit *)
    _fKnifeCmd  : LREAL;                   (* 刀速指令锁存副本（上一拍，R38），[mm/s] / the latched knife command copy, the previous scan *)
    _fKnifePos  : LREAL;                   (* 刀行进积分位置（本周期起点起算），[mm] / the integrated knife travel position *)
    _fDtSec     : LREAL;                   (* 扫描周期秒值（斜坡基值），[s] / the scan cycle in seconds *)
    _fAccStep   : LREAL;                   (* 每拍加速度增量，[mm/s] / the per scan acceleration increment *)
    _fDecStep   : LREAL;                   (* 每拍减速度增量，[mm/s] / the per scan deceleration increment *)
    _bInWin     : BOOL;                    (* 刀位在同步窗内标志，[标志] / the knife sits inside the sync window *)
    _tPhasePt   : TIME;                    (* 相计时器 PT 当前值（逐相选择）/ the timer PT for the current phase *)
    _bTimerIn   : BOOL;                    (* 相计时器 IN 条件（显式条件）/ the timer IN condition *)
END_VAR
VAR CONSTANT
    DL_FSS_FMAX : LREAL := 1.0E30;         (* 非有限筛查幅值上限，[mm 或 mm/s 或 mm/s²] / the finiteness screening cap *)
    DL_FSS_CMAX : UDINT := 16#FFFF_FFFE;   (* 拒收计数饱和上限（增量前预判）/ the reject counter saturation cap, pre-increment check *)
END_VAR

// 段 1｜出口预置（R256 统一出口预置 + 单拍位两段式的第一段）/ segment 1, preset every outlet
eState       := _ePhase;                   // 相出口先镜像寄存器 / mirror the phase register first
bCutTrig     := FALSE;                     // 剪切脉冲预清零（单拍收尾）/ preset the cut pulse false, single scan tail
bValid       := TRUE;                      // 可用标志预置真（故障相再清）/ preset valid true, cleared in the fault phase
bError       := FALSE;                     // 故障标志预清零 / preset the error flag false
nErrCode     := 0;                         // 错误码预置无错 / preset the code to zero
_bCutPulse   := FALSE;                     // 内部脉冲位预清零（次拍清，R187①）/ preset the internal pulse false, cleared next scan
_bTimerIn    := FALSE;                     // 计时条件预清零 / preset the timer condition false
_tPhasePt    := tAccelMax;                 // 计时 PT 预置缺省值 / preset the timer PT to the default

// 段 2｜沿检测实例无条件调用（规则 ⑦）/ segment 2, the edge instances, called unconditionally
_rtCut(CLK := bCutReq);                    // 切剪请求沿，每周期无条件刷新 / the cut request edge, refreshed every scan
_rtReset(CLK := bReset);                   // 复位沿，每周期无条件刷新 / the reset edge, refreshed every scan

// 段 3｜复位解除：唯一可到达的锁存解除边（R188）/ segment 3, the only latch release edge
IF _rtReset.Q THEN                         // 复位上升沿 / the reset rising edge
    _bFault     := FALSE;                  // 解除故障锁存 / release the fault latch
    _nCodeLatch := 0;                      // 清锁存码 / clear the latched code
    _ePhase     := E_DL_FssPhase.eIdle;    // 回待机相（安全相）/ back to the safe idle phase
    _fKnifeCmd  := 0.0;                    // 刀速指令归零 / zero the knife command
    _fKnifePos  := 0.0;                    // 刀行进积分清零 / clear the travel integration
    _bCutArmed  := FALSE;                  // 撤销切剪武装 / disarm the cut request
    _bInWin     := FALSE;                  // 清窗标志 / clear the window flag
END_IF

// 段 4｜组态守卫（边界一逐项点名 + 配比约束边界五，R272）/ segment 4, the configuration guard
_bCfgBad := (fShearLen <= 0.0)                                           // 切长非正 / a non positive shear length
         OR (fSyncWinLen <= 0.0)                                         // 同步窗长非正 / a non positive window length
         OR (fShearLen < fSyncWinLen)                                    // 切长小于窗长（无加速段可言）/ the shear length under the window length
         OR (fAccel <= 0.0)                                              // 加速度非正 / a non positive acceleration
         OR (fDecel <= 0.0)                                              // 减速度非正 / a non positive deceleration
         OR (fSyncTol <= 0.0)                                            // 匹配容差非正 / a non positive tolerance
         OR (tAccelMax < (tCycle + tCycle))                              // 加速超时小于两倍扫描周期（配比约束）/ the accel timeout under two scans
         OR (tSyncMax < (tCycle + tCycle))                               // 同步超时小于两倍扫描周期 / the sync timeout under two scans
         OR (tDecelMax < (tCycle + tCycle))                              // 减速超时小于两倍扫描周期 / the decel timeout under two scans
         OR (fShearLen <> fShearLen) OR ((fShearLen - fShearLen) <> 0.0) OR (ABS(fShearLen) > DL_FSS_FMAX)
         OR (fSyncWinLen <> fSyncWinLen) OR ((fSyncWinLen - fSyncWinLen) <> 0.0) OR (ABS(fSyncWinLen) > DL_FSS_FMAX)
         OR (fAccel <> fAccel) OR ((fAccel - fAccel) <> 0.0) OR (ABS(fAccel) > DL_FSS_FMAX)
         OR (fDecel <> fDecel) OR ((fDecel - fDecel) <> 0.0) OR (ABS(fDecel) > DL_FSS_FMAX)
         OR (fSyncTol <> fSyncTol) OR ((fSyncTol - fSyncTol) <> 0.0) OR (ABS(fSyncTol) > DL_FSS_FMAX);

// 段 5｜线速守卫：非有限或负值即无效（待机拒收 / 周期中锁存，边界二）/ segment 5, the velocity guard
_bVelBad := (fProductVel <> fProductVel) OR ((fProductVel - fProductVel) <> 0.0) // 线速非有限 / the speed non finite
         OR (fProductVel < 0.0)                                  // 线速为负 / a negative speed
         OR (ABS(fProductVel) > DL_FSS_FMAX);                    // 线速超幅值筛查 / the speed over the screening cap

// 段 6｜首次成因锁存（故障期不重推断，回放锁存码，R189）/ segment 6, the first-cause latch
IF NOT _bFault THEN                        // 未锁存才登记成因 / a cause is registered only while not latched
    IF _bCfgBad THEN                       // 组态非法优先归因（根因）/ the configuration first, the root cause
        _bFault     := TRUE;               // 置锁存 / latch it
        _nCodeLatch := 16#0002_3790;       // 故障级：组态非法 / fault level: an illegal configuration
        _ePhase     := E_DL_FssPhase.eFault; // 迁入故障相 / enter the fault phase
    ELSIF _bVelBad AND (_ePhase <> E_DL_FssPhase.eIdle) THEN // 周期中线速失效 / the speed failed mid cycle
        _bFault     := TRUE;               // 置锁存 / latch it
        _nCodeLatch := 16#0002_3797;       // 故障级：线速失效停机 / fault level: the speed failed in cycle
        _ePhase     := E_DL_FssPhase.eFault; // 迁入故障相 / enter the fault phase
    END_IF
END_IF

// 段 7｜斜坡基值换算（TIME 显式转 ms 再转秒，不依赖平台 TIME_TO_LREAL 语义差）/ segment 7, the ramp base conversion
_fDtSec   := DINT_TO_LREAL(TIME_TO_DINT(tCycle)) / 1000.0; // 扫描周期秒值（除子为常量 1000.0，无除零面）/ the cycle in seconds, a constant divisor
_fAccStep := fAccel * _fDtSec;             // 每拍加速增量，[mm/s] / the per scan accel increment
_fDecStep := fDecel * _fDtSec;             // 每拍减速增量，[mm/s] / the per scan decel increment

// 段 8｜相计时器 PT 选择与无条件调用（规则 ⑦，选相不依赖可跳过分支）/ segment 8, the timer PT selection and the unconditional call
IF _ePhase = E_DL_FssPhase.eAccel THEN     // 加速相 / the accel phase
    _tPhasePt := tAccelMax;                // 加速超时值 / the accel timeout
    _bTimerIn := TRUE;                     // 相内计时有效 / the timer runs inside the phase
ELSIF _ePhase = E_DL_FssPhase.eSyncTrack THEN // 同步跟踪相 / the sync track phase
    _tPhasePt := tSyncMax;                 // 同步超时值（窗积分停滞收口）/ the sync timeout
    _bTimerIn := TRUE;                     // 相内计时有效 / the timer runs
ELSIF _ePhase = E_DL_FssPhase.eDecel THEN  // 减速相 / the decel phase
    _tPhasePt := tDecelMax;                // 减速超时值 / the decel timeout
    _bTimerIn := TRUE;                     // 相内计时有效 / the timer runs
ELSE                                       // 其余相不参与计时（缺省分支，非状态机 ELSE）/ the other phases do not time
    _tPhasePt := tAccelMax;                // 缺省 PT，保证 PT 恒有定义 / a default PT, always defined
    _bTimerIn := FALSE;                    // 计时条件清零 / the timer condition cleared
END_IF
_tonPhase(IN := _bTimerIn, PT := _tPhasePt); // 每周期无条件调用 / called every scan without exception

// 段 8b｜失能与故障相输出回夹（R57 停机相输出清零，先于状态机执行）/ segment 8b, the disable and fault output clamping
IF _bFault THEN                            // 锁存故障相 / the latched fault phase
    _fKnifeCmd := 0.0;                     // 刀速指令归零（回夹执行输出）/ zero the command, clamp the outlet
    _bCutArmed := FALSE;                   // 撤销武装 / disarm
    _bInWin    := FALSE;                   // 清窗 / clear the window
ELSIF NOT bEn THEN                         // 失能相（操作态，不发码）/ the disabled phase, an operator state
    _fKnifeCmd := 0.0;                     // 失能单拍安全归零（边界三，不走斜坡）/ zeroed at once, no ramp
    _ePhase    := E_DL_FssPhase.eIdle;     // 状态回待机 / back to idle
    _bCutArmed := FALSE;                   // 撤销武装 / disarm
    _bInWin    := FALSE;                   // 清窗 / clear the window
END_IF

// 段 9｜相状态机（ENUM + CASE + ELSE 兜底，仅运行许可时执行）/ segment 9, the phase machine, run permit only
IF bEn AND NOT _bFault THEN                // 运行许可成立 / the run permit holds
CASE _ePhase OF
    E_DL_FssPhase.eIdle:                   // 待机相 / the idle phase
        IF _bVelBad THEN                   // 线速无效（待机拒收，不发指令）/ the speed invalid, refused at idle
            nErrCode := 16#0002_3796;      // 信息级：待机拒收（不置 bError，R45）/ info level: refused at idle
        ELSIF _rtCut.Q THEN                // 切剪请求上升沿（启动周期并武装）/ a cut request edge starts the cycle
            _bCutArmed := TRUE;           // 预武装本请求 / arm this request
            _fKnifePos := 0.0;            // 刀行进积分清零（周期起点）/ clear the travel integration
            _ePhase    := E_DL_FssPhase.eAccel; // 进入加速相 / enter the accel phase
        END_IF
    E_DL_FssPhase.eAccel:                  // 加速相 / the accel phase
        IF _rtCut.Q THEN                   // 非受理相请求到达 → 拒收计数 / a request in a non accepting phase, refused
            IF uCutRejCnt < DL_FSS_CMAX THEN // 饱和不回绕（增量前预判）/ saturating, no wrap
                uCutRejCnt := uCutRejCnt + 1; // 拒收计数递增 / increment the reject counter
            END_IF
            nErrCode := 16#0002_3795;      // 信息级：请求被拒收 / info level: the request refused
        END_IF
        IF ABS(_fKnifeCmd - fProductVel) <= fSyncTol THEN // 速度差进入容差带 / the speed gap inside the tolerance
            _fKnifeCmd := fProductVel;     // 贴合线速（消除残余差）/ snap onto the line speed
            _ePhase    := E_DL_FssPhase.eSyncTrack; // 进入同步跟踪相 / enter the sync track phase
        ELSE                               // 尚未匹配 / not matched yet
            _fKnifeCmd := _fKnifeCmd + _fAccStep; // 斜坡上抬（基于上一拍副本，R38）/ ramp up from the latched copy
            IF _fKnifeCmd > fProductVel THEN   // 越过目标（超调钳位，贴线速后不再上抬）/ over the target, clamp the overshoot
                _fKnifeCmd := fProductVel;     // 钳到目标 / clamp to the target
            END_IF
        END_IF
        _fKnifePos := _fKnifePos + _fKnifeCmd * _fDtSec; // 刀行进积分（加速段亦前进）/ the travel integration, the knife advances
        IF _tonPhase.Q THEN                // 加速相超时（归因唯一 3791）/ the accel phase timed out
            _bFault     := TRUE;           // 锁存故障 / latch the fault
            _nCodeLatch := 16#0002_3791;   // 故障级：加速超时 / fault level: the accel timed out
            _ePhase     := E_DL_FssPhase.eFault; // 迁入故障相 / enter the fault phase
        END_IF
    E_DL_FssPhase.eSyncTrack:              // 同步跟踪相 / the sync track phase
        _fKnifeCmd := fProductVel;         // 速度直接跟随线速（同步段不再斜坡）/ follow the line speed directly
        _fKnifePos := _fKnifePos + _fKnifeCmd * _fDtSec; // 刀行进积分 / the travel integration
        _bInWin    := (_fKnifePos >= (fShearLen - fSyncWinLen)); // 同步窗判定（闭区间下界）/ the window verdict, a closed lower bound
        IF _rtCut.Q THEN                   // 受理相请求到达 → 更新武装 / a request in the accepting phase, arm it
            _bCutArmed := TRUE;            // 受理 / accepted
        END_IF
        IF _bCutArmed AND _bInWin AND (ABS(_fKnifeCmd - fProductVel) <= fSyncTol) THEN // 窗内 + 已匹配 + 已武装 → 触发
            _ePhase := E_DL_FssPhase.eCutFire; // 进入剪切触发相（下拍发脉冲）/ enter the cut fire phase
        ELSIF _fKnifePos >= fShearLen THEN // 窗满未剪（同拍竞态闸：本拍事件已先消化）/ the window passed without a cut
            _bCutArmed := FALSE;           // 撤销武装 / disarm
            nErrCode   := 16#0002_3794;    // 信息级：窗满跳过 / info level: skipped
            _ePhase    := E_DL_FssPhase.eDecel; // 强制进减速清窗 / force the decel phase to clear the window
        ELSIF _tonPhase.Q THEN             // 同步跟踪相超时（归因唯一 3798，窗积分停滞的收口）/ the sync track timed out
            _bFault     := TRUE;           // 锁存故障 / latch the fault
            _nCodeLatch := 16#0002_3798;   // 故障级：同步超时 / fault level: the sync track timed out
            _ePhase     := E_DL_FssPhase.eFault; // 迁入故障相 / enter the fault phase
        END_IF
    E_DL_FssPhase.eCutFire:                // 剪切触发相（驻留一拍）/ the cut fire phase, one scan
        _bCutPulse := TRUE;                // 内部脉冲置位（段 10 统一映射，R187）/ set the internal pulse, mapped at segment 10
        _ePhase    := E_DL_FssPhase.eDecel; // 次拍转入减速相 / move to the decel phase next scan
    E_DL_FssPhase.eDecel:                  // 减速相 / the decel phase
        IF _rtCut.Q THEN                   // 非受理相请求到达 → 拒收计数 / a request in a non accepting phase, refused
            IF uCutRejCnt < DL_FSS_CMAX THEN // 饱和不回绕 / saturating
                uCutRejCnt := uCutRejCnt + 1; // 拒收计数递增 / increment the counter
            END_IF
            nErrCode := 16#0002_3795;      // 信息级：请求被拒收 / info level: refused
        END_IF
        _fKnifeCmd := _fKnifeCmd - _fDecStep; // 斜坡下降（基于上一拍副本，R38）/ ramp down from the latched copy
        IF _fKnifeCmd <= 0.0 THEN          // 已归零（MAX 钳位结果，非浮点判等）/ zeroed via the MAX clamp, no float equality
            _fKnifeCmd := 0.0;          // 精确归零 / exact zero
            _fKnifePos := 0.0;           // 刀位清零（下周期起点复位）/ clear the travel position
            _bInWin    := FALSE;         // 清窗 / clear the window
            _ePhase    := E_DL_FssPhase.eIdle; // 回待机 / back to idle
        END_IF
        IF _tonPhase.Q THEN                // 减速相超时（归因唯一 3792）/ the decel phase timed out
            _bFault     := TRUE;           // 锁存故障 / latch the fault
            _nCodeLatch := 16#0002_3792;   // 故障级：减速超时 / fault level: the decel timed out
            _ePhase     := E_DL_FssPhase.eFault; // 迁入故障相 / enter the fault phase
        END_IF
    E_DL_FssPhase.eFault:                  // 故障相（锁存保持，输出回夹已在段 8b 执行）/ the fault phase, outlets clamped at 8b
        bValid   := FALSE;                 // 出口不可信 / the outlets not trustworthy
        bError   := TRUE;                  // 故障标志置位 / raise the fault flag
        nErrCode := _nCodeLatch;           // 回放锁存码（不按当下输入重推断）/ replay the latched code
    ELSE                                   // 非法枚举兜底（回安全相 + 置码，规则 ⑥）/ the illegal enumeration guard
        _bFault     := TRUE;               // 置锁存 / latch it
        _nCodeLatch := 16#0002_3793;       // 故障级：非法相枚举 / fault level: an illegal phase value
        _ePhase     := E_DL_FssPhase.eFault; // 回安全相（故障相）/ force the safe fault phase
        bValid      := FALSE;              // 出口不可信 / not trustworthy
        bError      := TRUE;               // 故障标志置位（禁静默）/ raise the flag
        nErrCode    := _nCodeLatch;        // 回放锁存码 / replay the latched code
END_CASE
END_IF

// 段 10｜出口映射（名实双出口同源，单点写入，R191）/ segment 10, the outlet mapping
fKnifeVelCmd := _fKnifeCmd;                // 刀速指令出口 = 锁存副本（单点写入）/ the command outlet mirrors the register
bCutTrig     := _bCutPulse AND bEn AND NOT _bFault; // 剪切脉冲单拍出口（失能 / 故障禁发）/ the single scan pulse, gated
eState       := _ePhase;                   // 相出口 = 寄存器（段 9 之后不再触碰）/ the phase outlet, not touched after segment 9
IF _bFault THEN                            // 锁存故障相出口补充（含故障入口拍，指令即时归零回夹）/ the latched fault supplement, including the entry scan
    fKnifeVelCmd := 0.0;                   // 刀速指令归零（回夹执行输出）/ zero the command outlet
    bValid   := FALSE;                     // 出口不可信 / not trustworthy
    bError   := TRUE;                      // 故障标志 / the fault flag
    nErrCode := _nCodeLatch;               // 回放锁存码 / replay the latched code
END_IF
END_FUNCTION_BLOCK
