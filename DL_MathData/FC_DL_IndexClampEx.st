(*
    FC_DL_IndexClampEx —— 数组下标钳位原子（DINT 域）
    ------------------------------------------------------------------
    分类      : DL_MathData / Clamp
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托比较与选择语义，外围统一错误码/钳位/双语文档；
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R40）
    ------------------------------------------------------------------
    功能说明  : 数组下标钳位原子：将 nIdx 钳制到 [nLower, nUpper] 边界内并作为
                返回值输出，供全部数组访问前的防御性下标整备复用；
                越界按边界钳位：nIdx < nLower 钳至下界，置信息级 16#0001_049C；
                nIdx > nUpper 钳至上界，置信息级 16#0001_049D；
                上下界倒置（nLower > nUpper）判为故障级 16#0001_03DA，返回下界值
                且 bValid=FALSE（倒置边界意味着调用方组态错误，钳位结果无确定
                语义，拒绝输出并保持返回值落在下界侧防御值）；
                信息级码属正常防御：bError=FALSE、bValid=TRUE，输出钳位后防御值。
    错误码    : 16#0001_03DA 上下界倒置（nLower > nUpper）——故障级，返回下界值，bValid=FALSE
                16#0001_049C 下标低于下界，已钳至下界——信息级，正常防御
                16#0001_049D 下标高于上界，已钳至上界——信息级，正常防御
                （R90 反证句：下越界与上越界两场景均无法由返回值观测——钳位后输出
                  为合法边界值且 bValid=TRUE 与域内直通组合相同，若不占码则现场无法
                  还原越界方向，故两侧各占一码；倒置场景由 bValid=FALSE 加故障码
                  组合与信息级钳位区分，且与两个越界码的「方向语义」不同，故独立占码）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，
                非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-19 v1.0.0 首次入库（R40 · 批 4 · T0 快车道）
*)
FUNCTION FC_DL_IndexClampEx : DINT
VAR_INPUT
    nIdx    : DINT; // 待钳位下标 [索引] ｜ index to clamp
    nLower  : DINT; // 边界下界 [索引]，大于上界时判故障拒绝 ｜ lower bound, a fault is raised when greater than the upper bound
    nUpper  : DINT; // 边界上界 [索引]，小于下界时判故障拒绝 ｜ upper bound, a fault is raised when less than the lower bound
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常，16#0001_04XX=信息级，16#0001_03XX=故障级 ｜ error id, 0=ok, 16#0001_04XX=info, 16#0001_03XX=fault
    bError : BOOL;  // 是否出错，eErr 落故障级时为 TRUE ｜ fault flag, TRUE when eErr is fault level
    bValid : BOOL;  // 输出是否有效可用 ｜ output valid flag
END_VAR

// 段 1｜返回值与错误状态预置 ｜ segment 1, preset return value and error status
FC_DL_IndexClampEx := 0; // 故障缺省返回 0 [索引] ｜ fault default returns 0
eErr   := 0;     // 预置无错误 ｜ preset no error
bError := FALSE; // 预置无故障 ｜ preset no fault
bValid := FALSE; // 预置无效，通过防御闸后置位 ｜ preset invalid, set TRUE after guard passes

// 段 2｜上下界倒置防御闸（早退） ｜ segment 2, bound-inversion guard (early return)
IF nLower > nUpper THEN
    FC_DL_IndexClampEx := nLower; // 故障级返回下界侧防御值 [索引] ｜ fault level returns the lower-bound defensive value
    eErr   := 16#0001_03DA;       // 上下界倒置故障码 ｜ bound-inversion fault id
    bError := TRUE;               // 置故障标志（R45 配对）｜ raise the fault flag (R45 pairing)
    bValid := FALSE;              // 输出无效 ｜ output invalid
    RETURN;                       // 早退，不做钳位推断 ｜ early return, no clamping inference
END_IF

// 段 3｜双侧钳位主体（末段） ｜ segment 3, double-side clamp body (final)
IF nIdx < nLower THEN
    FC_DL_IndexClampEx := nLower; // 低于下界钳至下界 [索引] ｜ under the lower bound, clamp to it
    eErr := 16#0001_049C;         // 信息级：下越界已钳位 ｜ info level: under-range clamped
ELSIF nIdx > nUpper THEN
    FC_DL_IndexClampEx := nUpper; // 高于上界钳至上界 [索引] ｜ over the upper bound, clamp to it
    eErr := 16#0001_049D;         // 信息级：上越界已钳位 ｜ info level: over-range clamped
ELSE
    FC_DL_IndexClampEx := nIdx;   // 域内下标直通 [索引] ｜ in-domain index pass-through
END_IF
bError := FALSE; // 信息级钳位不置故障，故障分支已提前返回 ｜ info-level clamp never raises fault, fault branch has returned
bValid := TRUE;  // 域内或钳位输出均有效可用 ｜ in-domain or clamped output is valid
END_FUNCTION
