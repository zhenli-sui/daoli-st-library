(*
    FC_DL_ArrayCumSumLreal —— LREAL 数组前缀累计序列 + 总和出口（统计线）
    ------------------------------------------------------------------
    组件名称  : FC_DL_ArrayCumSumLreal
    分类      : DL_MathData / Statistics
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : 借鉴组织 —— T2-1 LGF · Math（统计线，矩阵行 157）：仅借鉴
                「前缀累计 / 累计序列输出」公开功能定义；clean-room 声明 ——
                零代码行复制，判据链 / 码位 / 钳位与拒绝口径 100% 自有；
                累加内核为 IEC 61131-3 标准算术的道莅防御性实现。
    平台      : 纯 IEC 61131-3（WHILE + LREAL 算术），无内建函数依赖，
                CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R72 构建轮 · 批 1 · 序号 3）
    ------------------------------------------------------------------
    功能说明  : 对有效样本数 nCount 个 LREAL 输入计算前缀累计序列
                afOut[i] = Σ afIn[1..i]（i = 1..nCount），并给总和出口
                fTotal = afOut[nCount]。真实工况：能耗 / 产量累计曲线、
                按片批次余量推演、OEE 累计谱。量纲随输入（m³ / kWh / 件 等），
                本件不解释量纲。
                判据链顺序：
                ① nCount 域闸：0 → 信息级空出口（fTotal = 0，afOut 不触碰，
                   bValid = TRUE）；> 数组上界 → 钳位照算 + 信息级；
                ② 逐元素非有限闸（两遍扫描第一遍，R151 闸全枚举）：**遇非有限
                   样本整体拒绝**（保守口径：部分累计会污染下游余量判断，
                   出故障级码，afOut 零写入）；
                ③ 循环累加（WHILE 带 DL_CUM_GUARD 防死锁计数器，两遍各自独立
                   计数）+ 写前下标双检；
                ④ 溢出面：累计 > 1E30 → 置 bTruncated 中断累加（保留至上一
                   有效前缀），信息级声明口径；非有限中间量同判（差值自反 +
                   自反双判，R79）。
                浮点判等禁用 =（红线 5）：本件无浮点相等比较。
    错误码    : 16#0002_3902 nCount = 0，空出口（fTotal = 0，bValid = TRUE）
                            —— 信息级，不置 bError（R45）
                16#0002_3903 nCount > 数组上界，已钳位照算 —— 信息级，值可用
                16#0002_3904 样本非有限或循环守卫越限（整体拒绝，afOut 零写入，
                            返回 FALSE）—— 故障级
                16#0002_3905 累计超 1E30 上界，已置 bTruncated 中断累加（保留
                            至上一有效前缀，bValid = TRUE）—— 信息级
                加码反证句（R90）：3902/3903/3905 均有独立输出观测面
                （3902 由 nCount=0 请求 + 空出口唯一对应；3903 由钳位行为 +
                部分结果唯一对应；3905 由 bTruncated 专位唯一对应），互不可
                由现有输出组合还原，故各立一码。
    码位总账  : 16#0002_3902 用 ｜ 16#0002_3903 用 ｜ 16#0002_3904 用 ｜
                16#0002_3905 用
    状态机    : N/A —— 纯函数无状态，无 CASE 可写，非法状态不可能出现
    边界与披露: 一 无定时器 / 无沿检测实例，周期安全规则 N/A；WHILE 双循环
                   各配 DL_CUM_GUARD 守卫（160 > 上界 128，正常不触发），
                   守卫越限并入 3904 故障级（结构性不可达防御收口）；
                二 零全局变量、零 VAR_EXTERNAL、零物理地址；
                三 域闸逐项点名（R272）：afIn[1..nEff] 全部元素纳入非有限闸；
                   nCount 域闸覆盖 0 / 上界两端点（各推一条向量）；
                四 数组写前下标双检（红线 2）：(nI >= 1) AND (nI <= DL_CUM_NMAX)
                   显式兜底；下标 > nCount 的 afOut 元素不被本件触碰；
                五 除法面：无（零除法，零除零面）；
                六 与 FC_DL_ArraySumLreal（DL_MathData）分工互引：后者只出
                   总和（可零拷贝、非有限剔除口径），本件输出**完整前缀序列**
                   （须写入调用方数组、整体拒绝口径），非变体，分工写死。
    验收向量  : V1 afIn = [1,2,3]，nCount = 3 → afOut = [1,3,6]，fTotal = 6；
                V2 nCount = 0 → 空出口 3902，fTotal = 0，afOut 不触碰；
                V3 nCount = 200（> 128）→ 钳位照算 3903；
                V4 afIn[2] = NaN → 3904 故障级，afOut 零写入；
                V5 累计越 1E30 → bTruncated = TRUE + 3905。
                算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    修订记录  : 2026-11-23 v1.0.0 首次入库（R72 构建轮 · 批 1 · 序号 3）
*)
FUNCTION FC_DL_ArrayCumSumLreal : BOOL
VAR_INPUT
    nCount    : UDINT;                     (* 有效样本数，[个]，0 = 空出口，超上界钳位照算 / the valid sample count *)
END_VAR
VAR_IN_OUT
    afIn      : ARRAY[1..DL_CUM_NMAX] OF LREAL;  (* 输入样本数组，[量纲随输入]，下标 1 起 / the input samples, unit follows the caller *)
    afOut     : ARRAY[1..DL_CUM_NMAX] OF LREAL;  (* 前缀累计序列出口，[量纲随输入]，afOut[i] = Σ afIn[1..i] / the prefix cumulative output *)
END_VAR
VAR_OUTPUT
    fTotal     : LREAL;                    (* 总和出口 = afOut[nCount]（截断时为最后有效前缀），[量纲随输入] / the total outlet *)
    bTruncated : BOOL;                     (* 累计越 1E30 上界截断标志 / the truncation flag *)
    bValid     : BOOL;                     (* 输出可用标志，故障级为 FALSE / the outputs usable flag *)
    bError     : BOOL;                     (* 故障标志，仅故障级码置位（R45 配对）/ the fault flag *)
    nInfoCode  : UDINT;                    (* 信息 / 错误码，0 = 正常 / the info or error id *)
END_VAR
VAR CONSTANT
    DL_CUM_NMAX  : INT  := 128;            (* 数组上界（两数组维度必须与本常量一致）[个] / the array upper bound, both arrays must match *)
    DL_CUM_NMAXU : UDINT := 128;           (* 数组上界的 UDINT 影子（nCount 域闸同口径比较用）[个] / the UDINT shadow of the bound *)
    DL_CUM_CAP   : LREAL := 1.0E30;        (* 累计幅值上界（截断口径）[量纲随输入] / the cumulative magnitude cap *)
    DL_CUM_GUARD : INT  := 160;            (* 循环守卫上限（> 上界 128，正常不触发）[次] / the loop guard limit *)
    DL_CUM_ZERO  : LREAL := 0.0;           (* 零哨兵 [量纲随输入] / the zero sentinel *)
    DL_CUM_ONE   : INT  := 1;              (* 游标步进与下界常量 [个] / the cursor step and lower bound *)
END_VAR
VAR
    nEff    : INT;                         (* 钳位后的有效样本数 [个] / the effective clamped count *)
    nI      : INT;                         (* 数组游标 [个] / the array cursor *)
    nGuard  : INT;                         (* 循环守卫计数器 [次] / the loop guard counter *)
    fRun    : LREAL;                       (* 累加器 [量纲随输入] / the running accumulator *)
    bFinOk  : BOOL;                        (* 第一遍有限性扫描结论 / the pass one finiteness verdict *)
    bStop   : BOOL;                        (* 第二遍截断中止标志 / the pass two truncation stop flag *)
    bSmpFin : BOOL;                        (* 当前样本有限性中间结论 / the per sample finiteness temporary *)
END_VAR

// 段 1｜返回值与状态预置（统一出口预置，R256）/ segment 1, preset the return and the status
FC_DL_ArrayCumSumLreal := FALSE;         // 故障缺省返回不可用 / the fault default is unusable
fTotal     := DL_CUM_ZERO;               // 总和出口预置零 / preset the total to zero
bTruncated := FALSE;                     // 截断标志预清零 / preset the truncation flag false
bValid     := FALSE;                     // 可用标志预清零 / preset the usable flag false
bError     := FALSE;                     // 故障标志预清零 / preset the fault flag false
nInfoCode  := 0;                         // 码位预置无错 / preset the code to zero
nEff    := 0;                            // 有效数预置零 / preset the effective count zero
nI      := 0;                            // 游标预置零 / preset the cursor zero
nGuard  := 0;                            // 守卫预置零 / preset the guard zero
fRun    := DL_CUM_ZERO;                  // 累加器清零 / clear the accumulator
bFinOk  := TRUE;                         // 有限性结论预置通过 / preset the finiteness verdict pass
bStop   := FALSE;                        // 截断标志预清零 / preset the stop flag false
bSmpFin := TRUE;                         // 样本有限性预置通过 / preset the per sample verdict pass

// 段 2｜nCount 域闸（0 = 空出口，超界 = 钳位照算，两端点向量）/ segment 2, the count domain gate
IF nCount = 0 THEN                       // 空请求：信息级空出口（afOut 不触碰）/ an empty request, the empty outlet
    nInfoCode := 16#0002_3902;           // 信息级：空出口 / info level: the empty outlet
    bError := FALSE;                     // 信息级不置故障（R45）/ info level never raises a fault
    bValid := TRUE;                      // 空出口按契约可用 / the empty outlet usable by contract
    FC_DL_ArrayCumSumLreal := TRUE;      // 照算完成（空）/ the pass complete, empty
    RETURN;                              // 结构早退 / structural exit
END_IF
IF nCount > DL_CUM_NMAXU THEN            // 请求超数组上界：钳位照算 / the request over the bound, clamped
    nInfoCode := 16#0002_3903;           // 信息级：已钳位照算 / info level: clamped
    nEff := DL_CUM_NMAX;                 // 钳到上界 / clamp to the bound
ELSE                                     // 域内请求 / the in domain request
    nEff := UDINT_TO_DINT(nCount);       // 降位转换（已证 <= 128，无回绕面）/ the narrowing conversion proven safe
END_IF

// 段 3｜第一遍：逐元素非有限扫描（整体拒绝口径，闸前零写入）/ segment 3, the pass one finiteness scan
nI     := DL_CUM_ONE;                    // 游标从下标 1 起 / the cursor from index one
nGuard := 0;                            // 守卫清零 / clear the guard
WHILE (nI <= nEff) AND (nGuard < DL_CUM_GUARD) DO // 守卫内扫描 / the scan inside the guard
    IF (nI >= DL_CUM_ONE) AND (nI <= DL_CUM_NMAX) THEN // 写前读前下标双检（红线 2）/ the index double check
        bSmpFin := NOT ((afIn[nI] <> afIn[nI]) OR ((afIn[nI] - afIn[nI]) <> 0.0)); // 自反 + 差值自反双判（R79）/ the reflexive pair test
        IF NOT bSmpFin THEN              // 非有限样本命中 / a non finite sample hit
            bFinOk := FALSE;             // 整体拒绝结论 / the overall reject verdict
            nI := nEff + DL_CUM_ONE;     // 跳出扫描（守卫内合法退出）/ break the scan legally
        END_IF
    END_IF
    nI := nI + DL_CUM_ONE;               // 游标推进 / advance the cursor
    nGuard := nGuard + DL_CUM_ONE;       // 守卫推进 / advance the guard
END_WHILE
IF (NOT bFinOk) OR (nGuard >= DL_CUM_GUARD) THEN // 非有限命中或守卫越限 / a hit or a guard overflow
    nInfoCode := 16#0002_3904;           // 故障级：样本序列不可信整体拒绝（守卫越限为结构性不可达防御收口）/ fault level: the samples untrusted
    bError := TRUE;                      // R45 配对置故障标志 / paired with the fault flag
    bValid := FALSE;                     // 输出不可用 / the outputs unusable
    FC_DL_ArrayCumSumLreal := FALSE;     // 拒绝返回 / the reject return
    RETURN;                              // 结构早退（afOut 保持零写入）/ exit with afOut untouched
END_IF

// 段 4｜第二遍：前缀累计与写出口（截断口径：累计 > 1E30 中断累加）/ segment 4, the pass two prefix accumulation
nI     := DL_CUM_ONE;                    // 游标复位 / reset the cursor
nGuard := 0;                             // 守卫复位 / reset the guard
WHILE (nI <= nEff) AND (nGuard < DL_CUM_GUARD) AND (NOT bStop) DO // 守卫与截断双出口 / the loop with both exits
    IF (nI >= DL_CUM_ONE) AND (nI <= DL_CUM_NMAX) THEN // 写前下标双检（红线 2）/ the index double check
        fRun := fRun + afIn[nI];         // 前缀累加（样本已过第一遍闸）/ the prefix accumulation
        IF (fRun <> fRun) OR ((fRun - fRun) <> 0.0) OR (fRun > DL_CUM_CAP) THEN // 溢出面：非有限中间量或越上界 / the overflow surface
            bTruncated := TRUE;          // 置截断标志 / raise the truncation flag
            nInfoCode := 16#0002_3905;   // 信息级：已截断（优先级高于钳位码 3903，声明口径）/ info level: truncated, overriding the clamp code
            bStop := TRUE;               // 中断累加（保留至上一有效前缀）/ stop the accumulation
        ELSE                             // 前缀有效 / the prefix valid
            afOut[nI] := fRun;           // 写前缀出口 / write the prefix outlet
        END_IF
    END_IF
    nI := nI + DL_CUM_ONE;               // 游标推进 / advance the cursor
    nGuard := nGuard + DL_CUM_ONE;       // 守卫推进 / advance the guard
END_WHILE

// 段 5｜正常出口 / segment 5, the normal outlet
fTotal := fRun;                          // 总和出口 = 最后有效前缀 / the total outlet, the last valid prefix
bError := FALSE;                         // 信息级不置故障（双保险）/ info level never raises a fault, second line
bValid := TRUE;                          // 输出可用 / the outputs usable
FC_DL_ArrayCumSumLreal := TRUE;          // 照算完成 / the pass complete
END_FUNCTION
