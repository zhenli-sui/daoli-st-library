(*
  FB_DL_CascadeWindupLink  —  串级外环→内环设定传递抗饱和联动 / Cascade windup link between outer and inner PID loops
  分类 Category : DL_Algo
  版本 Version  : 1.0.1
  来源 Source   : t2-5-modpid — 串级抗饱和族零检索深化
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 引用 FB_DL_PidController 引脚契约（不改其对外接口）：外环限幅镜像
                  内环限幅（fbOuter.rOutMin/rOutMax := fInnerMin/fInnerMax）；
                  2) 内环饱和（bLimitHigh/bLimitLow 任一）持续 tSatTo → 故障级 03AC/03AD
                  独立锁存（R190 归因唯一）；饱和期间外环经跟踪机制冻结积分：
                  fbOuter.bTrack := TRUE 且 fTrackValue := fbOuter.fOut（保持当前输出）；
                  3) R242 跟踪相退化推演：镜像钳制与冻结仅在 bTrack=FALSE 相生效——
                  调用方外部跟踪 bExtTrack=TRUE 期间，冻结请求让位（信息级 0494），
                  外部跟踪值直通；
                  4) 外环输出非有限 → 03AE 防御兜底锁存。
  返修记录 Rework  :
    2026-11-19  v1.0.1  R42 P0-3 中等返修：v1.0.0 故障相（段 7 故障分支）仅强制
                        bFreeze/bMirror 出口 FALSE，fbOuter.bTrack 残留 TRUE 且
                        fTrackValue 停更——跟踪标志与外环输出钳制名实不一，
                        外环静默冻结积分（P0 派单缺陷③，R191 名实双出口违反）。
                        修复要点：故障分支显式写 fbOuter.bTrack := FALSE
                        （跟踪释放，钳制语义与标志同拍同步），PID 回自主积分
                        由其自身安全侧承载；对外接口签名不变。
  边界 Boundary : ① 组态闸：fInnerMax <= fInnerMin → 03AB 锁存，镜像与冻结全部停发；
                  ② fbOuter 为 VAR_IN_OUT 引用：写其 rOutMin/rOutMax/bTrack/fTrackValue，
                  读其 fOut/bLimitHigh/bLimitLow/bLimitLow——不改 PidController 对外契约；
                  ③ 解除式全当拍量（R240 落地），逐 BOOL 标注见段 4；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : FB_DL_PidController（注入，不实例化，引脚按 registry 实名）；Standard.library（TON / R_TRIG）
  码表 Error codes（Algo 段 0002，窗口 03AB~03AE / 0491~0494）:
    16#0002_03AB 故障级：组态非法（内环限幅上下界颠倒），锁存至 bReset
    16#0002_03AC 故障级：内环上饱和持续（tSatTo），锁存至 bReset
    16#0002_03AD 故障级：内环下饱和持续（tSatTo），锁存至 bReset
    16#0002_03AE 故障级：外环输出非有限（防御兜底），锁存至 bReset
    16#0002_0491 信息级：镜像钳制生效沿（限幅镜像首次写入）
    16#0002_0492 信息级：外环积分冻结激活沿
    16#0002_0493 信息级：冻结解除恢复沿
    16#0002_0494 信息级：外部跟踪让位（bExtTrack 期间冻结请求被让位）
  修订历史 Revision :
    2026-11-19  v1.0.0  R41 首版（批次 3 · 序号 5）
    2026-11-19  v1.0.1  R42 P0-3 中等返修（见返修记录节）
*)

FUNCTION_BLOCK FB_DL_CascadeWindupLink
VAR_INPUT
    fInnerMin    : REAL := 0.0;       // 内环限幅下限 [%]，必须 < fInnerMax / Inner loop lower limit
    fInnerMax    : REAL := 100.0;     // 内环限幅上限 [%]，必须 > fInnerMin / Inner loop upper limit
    tSatTo       : TIME := T#1S;      // 饱和确认超时 [ms]，域 > 0 / Saturation confirm timeout
    bExtTrack    : BOOL := FALSE;     // 调用方外部跟踪请求 [-] / External tracking request from caller
    fExtTrackVal : REAL := 0.0;       // 外部跟踪值 [%] / External track value
    bEnable      : BOOL := FALSE;     // 联动使能 [-] / Link enable
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_IN_OUT
    fbOuter      : FB_DL_PidController;   // 外环 PID 引用（镜像钳制目标）/ Outer loop PID reference
    fbInner      : FB_DL_PidController;   // 内环 PID 引用（饱和判据来源）/ Inner loop PID reference
END_VAR
VAR_OUTPUT
    bFreeze      : BOOL;              // 外环冻结标志（实际生效）[-] / Effective freeze flag
    bMirror      : BOOL;              // 限幅镜像生效标志 [-] / Mirror active flag
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonSatHiTo   : TON;               // 上饱和确认定时器（专用超时命名），无条件刷新 / High-saturation timer
    tonSatLoTo   : TON;               // 下饱和确认定时器（专用超时命名），无条件刷新 / Low-saturation timer
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _bSatHigh    : BOOL;              // 内环上饱和当拍量 [-] / Inner high-saturation flag
    _bSatLow     : BOOL;              // 内环下饱和当拍量 [-] / Inner low-saturation flag
    _bHiLat      : BOOL;              // 上饱和锁存位（锁存量）/ High-saturation latch bit
    _bLoLat      : BOOL;              // 下饱和锁存位（锁存量）/ Low-saturation latch bit
    _bCfgBad     : BOOL;              // 组态锁存位（锁存量）/ Config-fault latch bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
    _bMirrorSent : BOOL;              // 镜像首次写入沿判据快照 / Mirror first-write edge snapshot
    _bFreezePrev : BOOL;              // 上拍冻结镜像（解除沿判据）/ Previous freeze mirror
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_bSatHigh := fbInner.bLimitHigh;                      // 内环上饱和（当拍量）
_bSatLow := fbInner.bLimitLow;                        // 内环下饱和（当拍量）
rtReset(CLK := bReset);                               // 复位沿（每拍必调）
tonSatHiTo(IN := bEnable AND _bSatHigh, PT := tSatTo);    // 上饱和确认（每拍必调）
tonSatLoTo(IN := bEnable AND _bSatLow, PT := tSatTo);     // 下饱和确认（每拍必调）

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bHiLat/_bLoLat/_bCfgBad 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
bFreeze := FALSE;                   // 冻结出口缺省 FALSE
bMirror := FALSE;                   // 镜像出口缺省 FALSE
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（当拍量判据） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bHiLat := FALSE;               // 清上饱和锁存位
    _bLoLat := FALSE;               // 清下饱和锁存位
    _bCfgBad := FALSE;              // 清组态锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF
IF fInnerMax <= fInnerMin THEN
    _uFault := 16#0002_03AB;        // 故障级：组态非法（限幅颠倒）
    _bCfgBad := TRUE;
END_IF

(* —— 段 3：限幅镜像（仅组态有效且使能相生效；R242：仅外环 bTrack=FALSE 相写入） —— *)
IF bEnable AND (NOT _bCfgBad) AND (NOT fbOuter.bTrack) THEN
    fbOuter.rOutMin := fInnerMin;   // 外环下限镜像内环
    fbOuter.rOutMax := fInnerMax;   // 外环上限镜像内环
    bMirror := TRUE;                // 镜像生效标志
    IF NOT _bMirrorSent THEN
        _uInfo := 16#0002_0491;     // 信息级：镜像钳制生效沿
        _bMirrorSent := TRUE;       // 沿单发
    END_IF
END_IF

(* —— 段 4：饱和锁存与解除（判据当拍量；解除式全当拍量，R240 落地） —— *)
IF tonSatHiTo.Q AND (NOT _bHiLat) THEN
    _uFault := 16#0002_03AC;        // 故障级：上饱和持续锁存
    _bHiLat := TRUE;
END_IF
IF tonSatLoTo.Q AND (NOT _bLoLat) THEN
    _uFault := 16#0002_03AD;        // 故障级：下饱和持续锁存
    _bLoLat := TRUE;
END_IF
(* 解除式逐 BOOL 标注（R240）：rtReset.Q = 当拍量；_bSatHigh/_bSatLow = 当拍量；
   均不含锁存量（_bHiLat/_bLoLat），解除边真实可达。 *)
IF rtReset.Q AND (NOT _bSatHigh) AND (NOT _bSatLow) AND (NOT _bCfgBad) THEN
    _bHiLat := FALSE;               // 清上饱和锁存位（锁存量，仅此当拍量解除沿可清）
    _bLoLat := FALSE;               // 清下饱和锁存位（锁存量，仅解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，仅本当拍量解除沿可清）
END_IF

(* —— 段 5：外环输出非有限防御兜底（NaN 自反判） —— *)
IF (fbOuter.fOut <> fbOuter.fOut) OR ((fbOuter.fOut - fbOuter.fOut) <> (fbOuter.fOut - fbOuter.fOut)) THEN
    _uFault := 16#0002_03AE;        // 故障级：外环输出非有限
    _bHiLat := TRUE;                // 并入聚合锁存（安全侧）
END_IF

(* —— 段 6：外环积分冻结联动（R242：bExtTrack 相冻结让位；冻结经跟踪机制承载） —— *)
IF bEnable AND (NOT _bCfgBad) AND (_bSatHigh OR _bSatLow) AND (NOT bExtTrack) THEN
    fbOuter.bTrack := TRUE;         // 冻结：跟踪机制接管
    fbOuter.fTrackValue := fbOuter.fOut;    // 跟踪值 = 当前输出（保持不积分）
    bFreeze := TRUE;                // 冻结生效标志
    IF NOT _bFreezePrev THEN
        _uInfo := 16#0002_0492;     // 信息级：冻结激活沿
    END_IF
ELSIF bEnable AND (NOT _bCfgBad) AND bExtTrack THEN
    fbOuter.bTrack := TRUE;         // 外部跟踪直通（调用方所有权）
    fbOuter.fTrackValue := fExtTrackVal;    // 外部跟踪值
    IF (_bSatHigh OR _bSatLow) THEN
        _uInfo := 16#0002_0494;     // 信息级：冻结请求被外部跟踪让位
    END_IF
ELSE
    fbOuter.bTrack := FALSE;        // 解除跟踪（恢复 PID 自主积分）
    IF _bFreezePrev THEN
        _uInfo := 16#0002_0493;     // 信息级：冻结解除恢复沿
    END_IF
END_IF

(* —— 段 7：出口单点映射（锁存码回放，禁同拍抹除） —— *)
IF (_bHiLat OR _bLoLat OR _bCfgBad) THEN
    nErrId := _uFault;              // 故障锁存码回放
    bFreeze := FALSE;               // 故障期冻结出口强制 FALSE（安全侧）
    bMirror := FALSE;               // 故障期镜像出口强制 FALSE（安全侧）
    fbOuter.bTrack := FALSE;        // 故障期跟踪标志与钳制同步释放（v1.0.1 名实一致，R191）
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bHiLat OR _bLoLat OR _bCfgBad;   // 故障标志与锁存位同源
_bFreezePrev := bFreeze;            // 冻结解除沿判据快照

END_FUNCTION_BLOCK
