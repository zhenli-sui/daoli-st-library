(*
    FC_DL_MuxIntEx —— MUX 八路选择防御包装（INT 域）
    ------------------------------------------------------------------
    分类      : DL_MathData / Mux
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托 MUX 内建选择语义，外围统一错误码/钳位/双语文档；
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R40）
    ------------------------------------------------------------------
    功能说明  : 八路 INT 选择器：按 uSel 选择 nIn0 至 nIn7 之一输出（0 基选择）；
                部分平台对 MUX 内建越路数选择的返回值未定义（有的返回 0、有的
                返回末路、有的触发异常），本件把越界行为显式化为钳位防御；
                选择值越路数时钳边界输出：uSel < 0 钳至通道 0，置信息级
                16#0001_0497；uSel > 7 钳至通道 7，置信息级 16#0001_0498；
                选择主体用 IF/ELSIF 链实现（IEC MUX 语义，不重实现选择内核），
                钳位保证选择值恒落在 [0, 7] 内，链分支全覆盖；
                链尾 ELSE 为理论不可达兜底（nSelC 已钳 [0, 7]，R128 口径：
                ELSE 只兜非法值）——命中时按选择下越界处置：钳回通道 0 并复用
                16#0001_0497（R90 复用不新占码位）；
                信息级码属正常防御：bError=FALSE、bValid=TRUE，输出钳位后防御值。
    错误码    : 16#0001_0497 选择值下越界（uSel < 0），已钳至通道 0——信息级，正常防御
                16#0001_0498 选择值上越界（uSel > 7），已钳至通道 7——信息级，正常防御
                （R90 反证句：下越界与上越界两场景均无法由返回值观测——钳位后输出
                  为合法通道值且 bValid=TRUE 与域内选择组合相同，若不占码则现场无法
                  还原「选错路」方向，故两侧各占一码）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 ENUM 状态可写，
                选择链 ELSE 兜底已在功能说明段声明
    修订记录  : 2026-11-19 v1.0.0 首次入库（R40 · 批 3 · T0 快车道）
*)
FUNCTION FC_DL_MuxIntEx : INT
VAR_INPUT
    uSel : INT; // 选择值（0 基），越界时钳至边界通道 ｜ selector (0-based), clamped to a boundary channel when out of range
    nIn0 : INT; // 通道 0 输入 [无量纲] ｜ channel 0 input
    nIn1 : INT; // 通道 1 输入 [无量纲] ｜ channel 1 input
    nIn2 : INT; // 通道 2 输入 [无量纲] ｜ channel 2 input
    nIn3 : INT; // 通道 3 输入 [无量纲] ｜ channel 3 input
    nIn4 : INT; // 通道 4 输入 [无量纲] ｜ channel 4 input
    nIn5 : INT; // 通道 5 输入 [无量纲] ｜ channel 5 input
    nIn6 : INT; // 通道 6 输入 [无量纲] ｜ channel 6 input
    nIn7 : INT; // 通道 7 输入 [无量纲] ｜ channel 7 input
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常，16#0001_04XX=信息级 ｜ error id, 0=ok, 16#0001_04XX=info level
    bError : BOOL;  // 是否出错，本件信息级防御不置 TRUE ｜ fault flag, never raised by the info-level defense of this unit
    bValid : BOOL;  // 输出是否有效可用 ｜ output valid flag
END_VAR
VAR CONSTANT
    DL_MUX_CH_MAX : INT := 7; // 最高通道号（八路 0 基）[通道] ｜ highest channel index (8 channels, 0-based)
END_VAR
VAR
    nSelC : INT; // 钳位后的有效选择值 [通道] ｜ clamped effective selector
END_VAR

// 段 1｜返回值与错误状态预置 ｜ segment 1, preset return value and error status
FC_DL_MuxIntEx := 0; // 故障缺省返回 0 [无量纲] ｜ fault default returns 0
eErr   := 0;     // 预置无错误 ｜ preset no error
bError := FALSE; // 预置无故障 ｜ preset no fault
bValid := FALSE; // 预置无效，通过防御闸后置位 ｜ preset invalid, set TRUE after guard passes
nSelC  := 0;     // 选择值清零 ｜ clear the selector

// 段 2｜选择值越界钳位 ｜ segment 2, selector out-of-range clamp
IF uSel < 0 THEN
    nSelC := 0;             // 下越界钳至通道 0 [通道] ｜ under-range clamp to channel 0
    eErr  := 16#0001_0497;  // 信息级：下越界已钳位 ｜ info level: under-range clamped
ELSIF uSel > DL_MUX_CH_MAX THEN
    nSelC := DL_MUX_CH_MAX; // 上越界钳至通道 7 [通道] ｜ over-range clamp to channel 7
    eErr  := 16#0001_0498;  // 信息级：上越界已钳位 ｜ info level: over-range clamped
ELSE
    nSelC := uSel;          // 域内选择值直通 [通道] ｜ in-domain selector pass-through
END_IF

// 段 3｜选择主体（IF/ELSIF 链，末段） ｜ segment 3, selection body (IF/ELSIF chain, final)
IF nSelC = 0 THEN
    FC_DL_MuxIntEx := nIn0; // 通道 0 输出 [无量纲] ｜ channel 0 output
ELSIF nSelC = 1 THEN
    FC_DL_MuxIntEx := nIn1; // 通道 1 输出 [无量纲] ｜ channel 1 output
ELSIF nSelC = 2 THEN
    FC_DL_MuxIntEx := nIn2; // 通道 2 输出 [无量纲] ｜ channel 2 output
ELSIF nSelC = 3 THEN
    FC_DL_MuxIntEx := nIn3; // 通道 3 输出 [无量纲] ｜ channel 3 output
ELSIF nSelC = 4 THEN
    FC_DL_MuxIntEx := nIn4; // 通道 4 输出 [无量纲] ｜ channel 4 output
ELSIF nSelC = 5 THEN
    FC_DL_MuxIntEx := nIn5; // 通道 5 输出 [无量纲] ｜ channel 5 output
ELSIF nSelC = 6 THEN
    FC_DL_MuxIntEx := nIn6; // 通道 6 输出 [无量纲] ｜ channel 6 output
ELSIF nSelC = 7 THEN
    FC_DL_MuxIntEx := nIn7; // 通道 7 输出 [无量纲] ｜ channel 7 output
ELSE
    // 理论不可达兜底（nSelC 已钳 [0, 7]）：按选择下越界处置，复用 0497 不新占码位（R90）
    FC_DL_MuxIntEx := nIn0; // 兜底输出通道 0 [无量纲] ｜ backstop output of channel 0
    eErr := 16#0001_0497;   // 复用下越界信息码 ｜ reuse the under-range info code
END_IF
bError := FALSE; // 信息级钳位不置故障 ｜ info-level clamp never raises fault
bValid := TRUE;  // 域内或钳位输出均有效可用 ｜ in-domain or clamped output is valid
END_FUNCTION
