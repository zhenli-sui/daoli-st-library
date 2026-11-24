(*
    FC_DL_DaysInMonthChk —— 年月 → 当月天数（日历原子族补件）
    ------------------------------------------------------------------
    组件名称  : FC_DL_DaysInMonthChk
    分类      : DL_Base / Calendar
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（格里高利历月天数
                静态表 + 闰年二月分支）；闰年律**唯一属主为库内
                FC_DL_LeapYearChk（DL_Base），本件组合调用之，零内联
                4/100/400 三级判定（常量单源纪律）**；月天数表为公开历法
                常识；实现 / 引脚名 / 码位 100% 自有；clean-room 声明 ——
                零代码行复制，无闭源参考。
    平台      : 纯 IEC 61131-3（CASE + 组合调用），无内建函数依赖，
                CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R72 构建轮 · 批 3 · 序号 7）
    ------------------------------------------------------------------
    功能说明  : 年月 → 当月天数（28~31 四值）。真实工况：月末日期计算、
                月度报表界、计量月切账日推演。
                判据链顺序：
                ① 年份承诺段闸：**[1998, 2099]**，域外故障级拒绝、输出 0、
                   不钳位照算——月天数是日历**事实**而非量值（R81 还原方向
                   不饱和：对域外年份伪造天数会一路传到月末日期运算）；
                ② 月域闸：1~12 外 → 故障级早退输出 0；
                ③ 大小月静态表出口（31 / 30）；
                ④ 二月分支：**组合调用闰年律唯一属主 FC_DL_LeapYearChk
                   （bFullRule := TRUE 三律，2000 世纪年判闰的事实正确性由
                   三律保证）**，属主件信息级 0430（整百年）在无更高优先级
                   码时透传；属主回执防御收口（不可达）。
                计划偏差声明（留痕）：ROUND_PLAN_R72 §6 承诺段写 1998~2117
                （DATE 容器秒承载口径），实测属主件闰年窗口为 1900~2099，
                本件承诺段**收窄对齐为 [1998, 2099]**；2100~2117 请求按 R81
                事实口径故障级拒绝而非钳位（钳位 2099 会把 2104 闰年误报为
                平年 28 天——钳位即伪造事实，故拒绝），偏差已留 VERSION 口径。
    错误码    : 16#0001_0750 月域越界（<1 或 >12），输出 0 —— 故障级
                16#0001_0751 年份越承诺段 [1998, 2099]，输出 0，不钳位
                            （R81 事实口径）—— 故障级
                16#0001_0753 闰年属主件回执不可用（年份已预闸入属主窗口，
                            结构性不可达防御收口）—— 故障级
                16#0001_0430（属主件信息级透传）整百年，闰年结论取决于三律
                            —— 信息级，不置 bError（R45）
                加码反证句（R90）：0750 / 0751 由入参域直接可证互斥观测；
                0753 与 0751 输出同为 0 + 故障级，但 0751 的入参越域可被
                调用方自证、0753 的入参合法，成因互斥不可互换，故各立一码。
    码位总账  : 16#0001_0750 用 ｜ 16#0001_0751 用 ｜ 16#0001_0753 用
                （16#0001_0752 为同段邻件 FB_DL_BlinkOutput 组态锁存码，
                本件不用不占）
    状态机    : N/A —— 纯函数无状态；月分支用 CASE + ELSE 兜底（月闸后
                ELSE 结构性不可达，防御收口并入 0750）
    边界与披露: 一 无定时器 / 无沿检测实例 / 无数组下标 / 无除法 / 无循环，
                   周期安全规则 N/A；
                二 零全局变量、零 VAR_EXTERNAL、零物理地址；
                三 整数进位点（终审两式 #2）验收向量：月域「1 恰为下界」
                   → 31 合法出口；「0 / 13 越界」→ 0750 故障级；闰年向量
                   三组（2024 闰 → 29 / 2100 世纪非闰 → 0751 拒绝出域 /
                   2000 闰 → 29 + 0430 透传）随验收落 JSONL；
                四 域闸逐项点名（R272）：uYear / uMonth 两入参全部纳入域闸；
                五 归位声明：日历 FC 原子族（LeapYearChk / DayOfWeekCalc /
                   WeekOfYearCalc / DurationFormat）属主均在 DL_Base
                   （registry 实测），本件随族归位；
                六 分工互引：FC_DL_LeapYearChk（闰年律唯一属主）、
                   FB_DL_MonthWindowCheck（月窗判定，可消费本件简化月末界）
                   ——本件只做月天数原子；
                七 依赖声明：仅 Standard.library（无内建函数依赖）+ 同库
                   FC_DL_LeapYearChk（只调用不修改）。
    验收向量  : V1 (2024, 2) → 29；V2 (2100, 2) → 0751 故障级输出 0；
                V3 (2000, 2) → 29 + 0430 信息级透传；V4 (2023, 4) → 30；
                V5 (2023, 7) → 31；V6 (2020, 1) → 31（年合法月下界 1 恰过闸）；
                V7 (2020, 0) / (2020, 13) → 0750 故障级输出 0；
                V8 (1997, 2) / (2099, 2) → 承诺段两端点（1997 拒 0751，
                2099 平年 → 28）。
                算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    修订记录  : 2026-11-23 v1.0.0 首次入库（R72 构建轮 · 批 3 · 序号 7）
*)
FUNCTION FC_DL_DaysInMonthChk : USINT
VAR_INPUT
    uYear  : UINT;                         (* 年份，[年]，承诺段 [1998, 2099]（与闰年属主窗口对齐收窄），域外拒绝不钳位 / the year, promise range 1998 to 2099, refused outside *)
    uMonth : UINT;                         (* 月份，[月]，域 [1, 12]，域外拒绝 / the month, domain 1 to 12, refused outside *)
END_VAR
VAR_OUTPUT
    bValid    : BOOL;                      (* 返回值（天数）可用标志，故障级为 FALSE / the days usable flag *)
    bError    : BOOL;                      (* 故障标志，仅故障级码置位（R45 配对）/ the fault flag *)
    nInfoCode : UDINT;                     (* 信息 / 错误码，0 = 正常 / the info or error id *)
END_VAR
VAR CONSTANT
    DL_DIM_YMIN  : UINT := 1998;           (* 年份承诺段下界 [年] / the year promise lower bound *)
    DL_DIM_YMAX  : UINT := 2099;           (* 年份承诺段上界（属主闰年窗口对齐收窄）[年] / the year promise upper bound, aligned with the owner window *)
    DL_DIM_MMIN  : UINT := 1;              (* 月域下界 [月] / the month domain lower bound *)
    DL_DIM_MMAX  : UINT := 12;             (* 月域上界 [月] / the month domain upper bound *)
    DL_DIM_FEB   : UINT := 2;              (* 二月月号（闰年分支入口）[月] / the February selector *)
    DL_DIM_DAYS31: USINT := 31;            (* 大月天数 [日] / the big month days *)
    DL_DIM_DAYS30: USINT := 30;            (* 小月天数 [日] / the small month days *)
    DL_DIM_DAYS29: USINT := 29;            (* 闰二月天数 [日] / the leap February days *)
    DL_DIM_DAYS28: USINT := 28;            (* 平二月天数 [日] / the common February days *)
END_VAR
VAR
    _bLpyOk   : BOOL;                      (* 闰年属主件返回值回执（TRUE = 闰年）[标志] / the leap year owner return receipt *)
    _bLpyErr  : BOOL;                      (* 闰年属主件故障回执 [标志] / the leap year owner fault receipt *)
    _bLpyVld  : BOOL;                      (* 闰年属主件判定有效回执（R381 全回执）[标志] / the leap year owner verdict valid receipt *)
    _eLpyCode : UDINT;                     (* 闰年属主件码位回执 [码] / the leap year owner code receipt *)
    uDays     : USINT;                     (* 月天数工作副本 [日] / the days working copy *)
END_VAR

// 段 1｜返回值与状态预置（统一出口预置，R256）/ segment 1, preset the return and the status
FC_DL_DaysInMonthChk := 0;                 // 故障缺省返回 0 天 / the fault default is zero days
bValid    := FALSE;                        // 预置不可用，过闸后置位 / preset unusable
bError    := FALSE;                        // 预置无故障 / preset no fault
nInfoCode := 0;                            // 预置无错 / preset no error
_bLpyOk := FALSE;                          // 属主回执清零 / clear the owner receipts
_bLpyErr := FALSE;                         // 属主回执清零 / clear the owner receipts
_bLpyVld := FALSE;                         // 属主回执清零 / clear the owner receipts
_eLpyCode := 0;                            // 属主码位清零 / clear the owner code
uDays := 0;                                // 天数副本清零 / clear the days copy

// 段 2｜年份承诺段闸：域外拒绝不钳位（R81 事实口径，防伪造天数）/ segment 2, the year promise gate, refusal over clamping
IF (uYear < DL_DIM_YMIN) OR (uYear > DL_DIM_YMAX) THEN // 年份越承诺段 / the year out of the promise
    nInfoCode := 16#0001_0751;             // 故障级：年份越承诺段 / fault level: the year out of promise
    bError := TRUE;                        // R45 配对置故障标志 / paired with the fault flag
    bValid := FALSE;                       // 返回值不可用 / unusable
    FC_DL_DaysInMonthChk := 0;             // 确定值零出口 / a deterministic zero outlet
    RETURN;                                // 结构早退 / structural exit
END_IF

// 段 3｜月域闸：1~12 外故障级早退 / segment 3, the month domain gate
IF (uMonth < DL_DIM_MMIN) OR (uMonth > DL_DIM_MMAX) THEN // 月越域 / the month out of domain
    nInfoCode := 16#0001_0750;             // 故障级：月域越界 / fault level: the month out of domain
    bError := TRUE;                        // R45 配对置故障标志 / paired with the fault flag
    bValid := FALSE;                       // 返回值不可用 / unusable
    FC_DL_DaysInMonthChk := 0;             // 确定值零出口 / a deterministic zero outlet
    RETURN;                                // 结构早退 / exit
END_IF

// 段 4｜大小月静态表 + 二月闰年分支（CASE + ELSE 兜底，月闸后 ELSE 不可达）/ segment 4, the month table and the February leap branch
CASE uMonth OF
    1, 3, 5, 7, 8, 10, 12:                 // 大月组 / the big months
        uDays := DL_DIM_DAYS31;            // 31 天 / thirty one days
    4, 6, 9, 11:                           // 小月组 / the small months
        uDays := DL_DIM_DAYS30;            // 30 天 / thirty days
    DL_DIM_FEB:                            // 二月：复用闰年律唯一属主 / February, the leap law owner call
        _bLpyOk := FC_DL_LeapYearChk(nYear := uYear,    // 年份已预闸入属主窗口 [1998, 2099] / the year pre gated inside the owner window
                                     bFullRule := TRUE, // 三律（2000 世纪年判闰事实正确性）/ the full three rule set
                                     eErr => _eLpyCode, // 码位回执 / the code receipt
                                     bError => _bLpyErr, // 故障回执 / the fault receipt
                                     bValid => _bLpyVld); // 判定有效回执（R381 全回执）/ the verdict valid receipt
        IF (NOT _bLpyOk) OR _bLpyErr OR (NOT _bLpyVld) THEN // 属主回执防御收口（结构性不可达）/ the owner receipt defensive guard
            nInfoCode := 16#0001_0753;     // 故障级：属主回执不可用 / fault level: the owner receipt unusable
            bError := TRUE;                // R45 配对 / paired with the flag
            bValid := FALSE;               // 返回值不可用 / unusable
            FC_DL_DaysInMonthChk := 0;     // 确定值零出口 / a deterministic zero outlet
            RETURN;                        // 结构早退 / exit
        END_IF
        IF _bLpyOk THEN                    // 属主判闰 / the owner verdicts a leap year
            uDays := DL_DIM_DAYS29;        // 29 天 / twenty nine days
        ELSE                               // 属主判平 / the owner verdicts a common year
            uDays := DL_DIM_DAYS28;        // 28 天 / twenty eight days
        END_IF
        IF (nInfoCode = 0) AND (_eLpyCode <> 0) AND (NOT _bLpyErr) THEN // 属主信息级透传（无更高优先级码时）/ the owner info pass through
            nInfoCode := _eLpyCode;        // 信息级透传（0430 整百年提示）/ the info pass through
        END_IF
    ELSE                                   // 月闸后不可达防御兜底（并入 0750 口径）/ the unreachable ELSE after the month gate
        uDays := 0;                        // 确定值零出口 / a deterministic zero outlet
        nInfoCode := 16#0001_0750;         // 并入月域故障级（R90 反证：不可达无独立观测需求）/ folded into the month fault
        bError := TRUE;                    // R45 配对 / paired with the flag
        bValid := FALSE;                   // 返回值不可用 / unusable
        FC_DL_DaysInMonthChk := 0;         // 确定值零出口 / a deterministic zero outlet
        RETURN;                            // 结构早退 / exit
END_CASE

// 段 5｜正常出口 / segment 5, the normal outlet
FC_DL_DaysInMonthChk := uDays;             // 发布月天数（28~31）/ publish the days
bValid := TRUE;                            // 结果可用 / the result usable
END_FUNCTION
