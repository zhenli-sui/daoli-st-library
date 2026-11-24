(*
    FC_DL_HmsToTodChk —— 时 / 分 / 秒三分量合成 TOD（HMI 组态入口）
    ------------------------------------------------------------------
    组件名称  : FC_DL_HmsToTodChk
    分类      : DL_MathData / TimeOfDay
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（三分量组态合成 +
                域闸钳位口径）；TOD 合成内核**委托库内属主件
                FC_DL_DintMsToTod（DL_MathData，毫秒计数口径唯一属主）**，
                本件零内联 ms→TOD 转换（T0 委托纪律）；判据顺序与
                FC_DL_DurationFormat 域外钳位口径对齐（库内复用）；
                引脚名 / 码位 100% 自有；clean-room 声明 —— 零代码行复制。
    平台      : 纯 IEC 61131-3（UDINT 域闸 + 常量乘法 + 委托调用），
                CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R72 构建轮 · 批 2 · 序号 6）
    ------------------------------------------------------------------
    功能说明  : HMI 三字段组态入口（时 / 分 / 秒各自独立输入）合成当日时刻
                TOD。真实工况：班次时刻 / 窗口时刻设定，与
                FB_DL_TimeWindowCheck / FB_DL_OccScheduleWindow 联用。
                判据链顺序：
                ① 分量非负闸：UDINT 天然非负，仅声明（无负值路径，闸空转）；
                ② 组合域闸（UDINT 域内先钳位后降位，防 UDINT→DINT 回绕）：
                   uHours > 23 → 钳 23；uMins > 59 → 钳 59；uSecs > 59 →
                   钳 59，**钳位照算 + 信息级**（与 FC_DL_DurationFormat 口径
                   对齐，不拒收——HMI 误输入尽量给出可用的最近合法时刻）；
                ③ 合成毫秒 nTotalMs = 时×3600000 + 分×60000 + 秒×1000：
                   上界推演 23×3600000 + 59×60000 + 59×1000 = 86399999
                   < 2^31 = 2147483648，钳位先行故乘法**无溢出面**（乘子全
                   常量，R382 常量除子 / 乘子级联口径）；
                ④ 委托属主件 FC_DL_DintMsToTod 合成 TOD（bClampSilently :=
                   TRUE——本件已钳到属主域 [0, 86399999] 内，属主钳位路径
                   结构性不可达），全 4 出参完整回执（R381 全回执纪律）；
                ⑤ 属主回执防御收口（回执不可用 → 故障级早退，结构性不可达）。
    错误码    : 16#0002_3909 分量越域（时 > 23 / 分 > 59 / 秒 > 59），已钳位
                            照算，bValid = TRUE —— 信息级，不置 bError（R45）
                16#0002_3910 属主件回执不可用（委托防御收口，结构性不可达）
                            —— 故障级
                加码反证句（R90）：3910 场景无法由 3909 + 正常返回观测——钳位
                路径 bValid = TRUE 且 TOD 有效，3910 是 bValid = FALSE 的
                不可用出口，输出组合不可互换观测，故立独立码。
    码位总账  : 16#0002_3909 用 ｜ 16#0002_3910 用
    状态机    : N/A —— 纯函数无状态，无 CASE 可写，非法状态不可能出现
    边界与披露: 一 无定时器 / 无沿检测实例 / 无数组下标 / 无除法（乘子常量
                   级联），周期安全规则 N/A；
                二 零全局变量、零 VAR_EXTERNAL、零物理地址；
                三 整数进位点（终审两式 #2）验收向量：「23:59:59 恰为上界」→
                   86399999 ms 正常出口不置码；「24:00:00 越界」→ 钳位
                   23:59:59 + 信息级 3909；
                四 域闸逐项点名（R272）：uHours / uMins / uSecs 三入参全部
                   纳入组合域闸，缺一即钳位静默失效；
                五 降位可表性：uHours ≤ 23 / uMins ≤ 59 / uSecs ≤ 59 已在
                   UDINT 域钳位后才 UDINT_TO_DINT，降位无回绕面（先钳后降
                   顺序写死，禁颠倒）；
                六 分工互引：FC_DL_TodToDintMs / FC_DL_DintMsToTod（毫秒计数
                   口径，后者为本件委托属主）、FC_DL_TimeToHmsString（TIME→
                   "hh:mm:ss" 文本）——本件为其组态侧反向语义，非文本变体；
                七 依赖声明：Standard.library（无内建函数依赖）+ 同库
                   FC_DL_DintMsToTod（只调用不修改）。
    验收向量  : V1 (8, 30, 0) → 08:30:00 正常出口；V2 (23, 59, 59) →
                86399999 ms 上界正常出口；V3 (24, 0, 0) → 钳位 23:59:59 +
                3909；V4 (0, 60, 0) → 钳位 00:59:00 + 3909；
                V5 (4294967295, 0, 0) → 钳位 23:00:00 + 3909（UDINT 域闸
                先行，降位无回绕向量）。
                算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    修订记录  : 2026-11-23 v1.0.0 首次入库（R72 构建轮 · 批 2 · 序号 6）
*)
FUNCTION FC_DL_HmsToTodChk : TOD
VAR_INPUT
    uHours : UDINT;                        (* 时分量，[时]，域 0~23，越域钳位照算 / the hours component, clamped outside *)
    uMins  : UDINT;                        (* 分分量，[分]，域 0~59，越域钳位照算 / the minutes component, clamped outside *)
    uSecs  : UDINT;                        (* 秒分量，[秒]，域 0~59，越域钳位照算 / the seconds component, clamped outside *)
END_VAR
VAR_OUTPUT
    bValid    : BOOL;                      (* 返回值（TOD）可用标志，故障级为 FALSE / the TOD usable flag *)
    bError    : BOOL;                      (* 故障标志，仅故障级码置位（R45 配对）/ the fault flag *)
    nInfoCode : UDINT;                     (* 信息 / 错误码，0 = 正常 / the info or error id *)
END_VAR
VAR CONSTANT
    DL_HMS_HMAX : UDINT := 23;             (* 时分量域上界 [时] / the hours domain upper bound *)
    DL_HMS_MMAX : UDINT := 59;             (* 分分量域上界 [分] / the minutes domain upper bound *)
    DL_HMS_SMAX : UDINT := 59;             (* 秒分量域上界 [秒] / the seconds domain upper bound *)
    DL_HMS_MSH  : DINT := 3600000;         (* 每小时毫秒数（常量乘子级联，R382）[ms] / the milliseconds per hour *)
    DL_HMS_MSM  : DINT := 60000;           (* 每分钟毫秒数 [ms] / the milliseconds per minute *)
    DL_HMS_MSS  : DINT := 1000;            (* 每秒毫秒数 [ms] / the milliseconds per second *)
END_VAR
VAR
    uHClamp : UDINT;                       (* 钳位后时分量 [时] / the clamped hours *)
    uMClamp : UDINT;                       (* 钳位后分分量 [分] / the clamped minutes *)
    uSClamp : UDINT;                       (* 钳位后秒分量 [秒] / the clamped seconds *)
    nH      : DINT;                        (* 降位时分量 [时] / the narrowed hours *)
    nM      : DINT;                        (* 降位分分量 [分] / the narrowed minutes *)
    nS      : DINT;                        (* 降位秒分量 [秒] / the narrowed seconds *)
    nTotalMs : DINT;                       (* 合成当日毫秒（上界 86399999 已证可表）[ms] / the composed day milliseconds *)
    _bMsErr : BOOL;                        (* 属主件故障回执 [标志] / the owner FC fault receipt *)
    _bMsVld : BOOL;                        (* 属主件输出可用回执（R381 全回执）[标志] / the owner FC usable receipt *)
    _bMsClmp: BOOL;                        (* 属主件钳位回执（结构性恒 FALSE，收下备用）[标志] / the owner FC clamp receipt *)
    _eMsCode: UDINT;                       (* 属主件码位回执 [码] / the owner FC code receipt *)
END_VAR

// 段 1｜返回值与状态预置（统一出口预置，R256）/ segment 1, preset the return and the status
FC_DL_HmsToTodChk := T#0S;                 // 故障缺省返回当日零点 / the fault default is midnight
bValid    := FALSE;                        // 预置不可用，过闸后置位 / preset unusable
bError    := FALSE;                        // 预置无故障 / preset no fault
nInfoCode := 0;                            // 预置无错 / preset no error
uHClamp := 0;                              // 钳位中间量清零 / clear the clamped hours
uMClamp := 0;                              // 钳位中间量清零 / clear the clamped minutes
uSClamp := 0;                              // 钳位中间量清零 / clear the clamped seconds
nH := 0;                                   // 降位中间量清零 / clear the narrowed hours
nM := 0;                                   // 降位中间量清零 / clear the narrowed minutes
nS := 0;                                   // 降位中间量清零 / clear the narrowed seconds
nTotalMs := 0;                             // 合成毫秒清零 / clear the composed milliseconds
_bMsErr := FALSE;                          // 属主回执清零 / clear the owner receipts
_bMsVld := FALSE;                          // 属主回执清零 / clear the owner receipts
_bMsClmp := FALSE;                         // 属主回执清零 / clear the owner receipts
_eMsCode := 0;                             // 属主码位清零 / clear the owner code

// 段 2｜分量非负闸（UDINT 天然非负，仅声明；无负值路径，闸空转）/ segment 2, the non negative declaration gate
// UDINT 域无负值路径，本闸为声明性空转（R272 全枚举中的口径声明行）。
// The UDINT domain has no negative path, this gate is a declarative no op.

// 段 3｜组合域闸：UDINT 域内先钳位后降位（防 UDINT→DINT 回绕，先钳后降顺序写死）/ segment 3, the combined domain gate with clamp before narrowing
IF uHours > DL_HMS_HMAX THEN               // 时越上界 / the hours over the bound
    uHClamp := DL_HMS_HMAX;                // 钳到 23 / clamp to 23
ELSE                                       // 时在域内 / the hours inside
    uHClamp := uHours;                     // 原值接管 / take the raw value
END_IF
IF uMins > DL_HMS_MMAX THEN                // 分越上界 / the minutes over the bound
    uMClamp := DL_HMS_MMAX;                // 钳到 59 / clamp to 59
ELSE                                       // 分在域内 / the minutes inside
    uMClamp := uMins;                      // 原值接管 / take the raw value
END_IF
IF uSecs > DL_HMS_SMAX THEN                // 秒越上界 / the seconds over the bound
    uSClamp := DL_HMS_SMAX;                // 钳到 59 / clamp to 59
ELSE                                       // 秒在域内 / the seconds inside
    uSClamp := uSecs;                      // 原值接管 / take the raw value
END_IF
IF (uHours > DL_HMS_HMAX) OR (uMins > DL_HMS_MMAX) OR (uSecs > DL_HMS_SMAX) THEN // 任一分量越域 / any component out of domain
    nInfoCode := 16#0002_3909;             // 信息级：钳位照算（DurationFormat 对齐口径）/ info level: clamped
    bError := FALSE;                       // 信息级不置故障（R45）/ info level never raises a fault
END_IF

// 段 4｜降位与毫秒合成（乘子全常量级联，上界 86399999 < 2^31 无溢出面）/ segment 4, narrowing and the millisecond composition
nH := UDINT_TO_DINT(uHClamp);              // 降位时分量（已证 <= 23）/ narrow the hours proven safe
nM := UDINT_TO_DINT(uMClamp);              // 降位分分量（已证 <= 59）/ narrow the minutes
nS := UDINT_TO_DINT(uSClamp);              // 降位秒分量（已证 <= 59）/ narrow the seconds
nTotalMs := (nH * DL_HMS_MSH) + (nM * DL_HMS_MSM) + (nS * DL_HMS_MSS); // 常量乘子合成 / the composition with constant multipliers

// 段 5｜委托属主件合成 TOD（返回值 TOD 直接承接；bClampSilently := TRUE，
//        属主钳位路径结构性不可达；全 4 出参完整回执，R381）/ segment 5, the delegated TOD composition
FC_DL_HmsToTodChk := FC_DL_DintMsToTod(nMsOfDay := nTotalMs, // 当日毫秒入参（已证在属主域内）/ the day milliseconds inside the owner domain
                                       bClampSilently := TRUE, // 钳位静默选向（本件已钳，属主钳位不可达）/ the silent clamp selector
                                       eErr => _eMsCode,       // 码位回执 / the code receipt
                                       bError => _bMsErr,      // 故障回执 / the fault receipt
                                       bValid => _bMsVld,      // 输出可用回执（R381 全回执）/ the usable receipt
                                       bClamped => _bMsClmp);  // 钳位回执 / the clamp receipt
IF _bMsErr OR (NOT _bMsVld) THEN           // 属主回执防御收口（结构性不可达）/ the owner receipt defensive guard
    nInfoCode := 16#0002_3910;             // 故障级：属主回执不可用 / fault level: the owner receipt unusable
    bError := TRUE;                        // R45 配对置故障标志 / paired with the fault flag
    bValid := FALSE;                       // 返回值不可用 / the return unusable
    FC_DL_HmsToTodChk := T#0S;             // 确定值零点出口 / a deterministic midnight outlet
    RETURN;                                // 结构早退 / structural exit
END_IF

// 段 6｜正常出口 / segment 6, the normal outlet
bValid := TRUE;                            // 结果可用 / the result usable
END_FUNCTION
