(*
    FC_DL_LerpClamped —— 线性插值（t 域钳位，端点外不外推）
    ------------------------------------------------------------------
    组件名称  : FC_DL_LerpClamped
    分类      : DL_MathData / Interpolation
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : 借鉴点 —— 数值分析中带参数域钳位的两点线性插值（lerp）语义，
                即 clamp 后的凸组合形式 y = a + (b - a) * clamp(t, 0, 1)；
                该形式在 t 超出 [0,1] 时**退回端点值**而不外推，是设定值过渡、
                配方插值、执行器软过渡的通行做法。
                clean-room 声明 —— 零代码行复制，只使用标准算术运算符与标准
                标准库函数 ABS；域闸 / 饱和 / 码位 / 双语文档全部自有。
                许可证 —— 本件 MIT；来源标签 self-std（道莅自有内规族），
                参考语义为公开数值方法常识，无第三方源码继承。
    平台      : 纯 IEC 61131-3，CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R70 构建轮 · 批 1 · N2）
    ------------------------------------------------------------------
    功能说明  : 对端点 fA、fB 依参数 fT 做线性插值，fT 先钳到 [0,1]。
                「不外推」是本件与裸 lerp 的唯一语义差别：fT < 0 返回 fA，
                fT > 1 返回 fB，中间按凸组合。
                非有限闸（R272 逐项点名，含换算与限值）：fA / fB / fT 三入参
                全部纳入 NaN 自反判 + Inf 差值自反判 + 幅值 1E30 上界筛查；
                闸不通过时**结构早退**并返回安全缺省值 fA（端点 A 为稳态值，
                不是中间插值，避免故障时输出一个凭空构造的中间量）。
                凸组合实现口径（关键设计）：先算 fT 钳位值 fTc，再算
                差值 fB - fA，最后 fA + 差值 * fTc。差值可能超 LREAL 域，
                故对中间量做**结果非有限复检**：若委托乘法后结果非有限，
                按端点就近原则饱和到 fB 或 fA 并报信息级，绝不把 Inf 送下游。
                本件无除法（凸组合形式不带除法），故不存在除零面。
    错误码    : 16#0002_0111 入参非有限（NaN / Inf / 超幅值），返回 fA —— 故障级
                16#0002_0112 插值结果非有限，已饱和至端点 —— 信息级，值可用
    码位总账  : 16#0002_0111 用 ｜ 16#0002_0112 用
    状态机    : R6 N/A —— 纯函数无状态，无 CASE 可写，非法状态不可能出现
    边界与披露: 一 无定时器 / 无边沿实例 / 无数组下标，周期安全规则 N/A；
                二 零全局变量、零 VAR_EXTERNAL、零物理地址；
                三 bClamped 表示 fT 曾被钳位（含恰为 0 / 1 的边界情形，
                   判据为钳位前后是否同值，不含容差 —— 布尔判据非浮点判据，
                   但比较用差值容差口径以避开浮点直比）；
                四 结果非有限分支置「端点 + 信息级」而非故障级：饱和是防御
                   动作、值仍可用于下游限幅链路，R45 口径要求信息级不置 bError。
    修订记录  : 2026-11-22 v1.0.0 首次入库（R70 构建轮 · 批 1 · N2）
*)
FUNCTION FC_DL_LerpClamped : LREAL
VAR_INPUT
    fA : LREAL;                            (* 端点 A 的值，[工程单位] / the value at endpoint A *)
    fB : LREAL;                            (* 端点 B 的值，[工程单位] / the value at endpoint B *)
    fT : LREAL;                            (* 插值参数，[0..1] 为有效域，域外钳位 / the interpolation parameter, clamped to 0..1 *)
END_VAR
VAR_OUTPUT
    eErr     : UDINT;                      (* 错误码，0 = 正常 / the error id, 0 = ok *)
    bError   : BOOL;                       (* 故障标志，故障级码时 TRUE / the error flag, TRUE on fault level *)
    bValid   : BOOL;                       (* 返回值可用，故障级为 FALSE / the return usable, FALSE on fault level *)
    bClamped : BOOL;                       (* fT 曾被钳到 [0,1] 域内，[标志] / the parameter was clamped into 0..1 *)
    fTUsed   : LREAL;                      (* 实际参与运算的钳位后参数，[无量纲] / the clamped parameter actually used *)
END_VAR
VAR CONSTANT
    DL_LRP_FMAX : LREAL := 1.0E30;         (* 非有限筛查幅值上限，[工程单位] / the finiteness screening cap *)
    DL_LRP_TOL  : LREAL := 1.0E-12;        (* 参数域钳位的比较容差，[无量纲] / the clamp comparison tolerance *)
END_VAR
VAR
    _fT  : LREAL;                          (* 钳位后的参数（内部中间量），[无量纲] / the clamped parameter, an internal temporary *)
    _fD  : LREAL;                          (* 端点差值 fB - fA（内部中间量），[工程单位] / the endpoint delta, an internal temporary *)
    _fY  : LREAL;                          (* 插值结果（内部中间量），[工程单位] / the interpolation result, an internal temporary *)
END_VAR

// 段 1｜返回值与状态预置（四段式第一段）/ segment 1, preset the return and the status
FC_DL_LerpClamped := fA;               // 故障缺省返回端点 A（稳态值）/ the fault default is endpoint A, a steady value
eErr     := 0;                         // 预置无错误 / preset no error
bError   := FALSE;                     // 预置无故障 / preset no fault
bValid   := FALSE;                     // 预置不可用，过闸后置位 / preset unusable, set TRUE after the gates
bClamped := FALSE;                     // 预置未钳位 / preset not clamped
fTUsed   := 0.0;                       // 预置参数出口零值 / preset the parameter outlet to zero

// 段 2｜三入参非有限闸（NaN 自反判 + Inf 差值自反判 + 幅值上界，R272 逐项点名）/ segment 2, the finiteness gate
IF (fA <> fA) OR ((fA - fA) <> 0.0) OR (ABS(fA) > DL_LRP_FMAX) THEN   // 端点 A 非有限 / endpoint A non finite
    eErr   := 16#0002_0111;            // 故障级：入参非有限 / fault level: a non finite input
    bError := TRUE;                    // R45 配对置故障标志 / paired with the code
    bValid := FALSE;                   // 返回值不可用 / the return is unusable
    RETURN;                            // 结构早退 / structural exit
END_IF
IF (fB <> fB) OR ((fB - fB) <> 0.0) OR (ABS(fB) > DL_LRP_FMAX) THEN   // 端点 B 非有限 / endpoint B non finite
    eErr   := 16#0002_0111;            // 故障级：入参非有限 / fault level: a non finite input
    bError := TRUE;                    // R45 配对 / paired with the code
    bValid := FALSE;                   // 返回值不可用 / the return is unusable
    RETURN;                            // 结构早退 / structural exit
END_IF
IF (fT <> fT) OR ((fT - fT) <> 0.0) OR (ABS(fT) > DL_LRP_FMAX) THEN   // 插值参数非有限 / the parameter non finite
    eErr   := 16#0002_0111;            // 故障级：入参非有限 / fault level: a non finite input
    bError := TRUE;                    // R45 配对 / paired with the code
    bValid := FALSE;                   // 返回值不可用 / the return is unusable
    RETURN;                            // 结构早退 / structural exit
END_IF

// 段 3｜参数域闸：t 钳到 [0,1]，域外不外推 / segment 3, the parameter domain clamp
_fT := fT;                             // 取参数原值 / take the raw parameter
IF fT < 0.0 THEN                       // 低于下域界 / under the lower domain edge
    _fT := 0.0;                        // 钳到 0，输出退回端点 A / clamp to zero, fall back to endpoint A
    bClamped := TRUE;                  // 记录已钳位 / record the clamp
ELSIF fT > 1.0 THEN                    // 高于上域界 / over the upper domain edge
    _fT := 1.0;                        // 钳到 1，输出退回端点 B / clamp to one, fall back to endpoint B
    bClamped := TRUE;                  // 记录已钳位 / record the clamp
END_IF
fTUsed := _fT;                         // 参数出口（钳位后真值）/ the parameter outlet, the clamped value

// 段 4｜凸组合委托：端点 + 差值 × 钳位参数（无除法，无除零面）/ segment 4, the convex combination kernel
_fD := fB - fA;                        // 端点差值，[工程单位] / the endpoint delta
_fY := fA + _fD * _fT;                 // 插值结果（委托 `+` 与 `*`）/ the interpolation result, delegated
IF (_fY <> _fY) OR ((_fY - _fY) <> 0.0) THEN   // 结果非有限（差值超域所致）/ the result came out non finite
    IF (ABS(_fT - 1.0) <= DL_LRP_TOL) THEN     // 参数贴 1 侧 / the parameter sits at the upper edge
        FC_DL_LerpClamped := fB;       // 饱和到端点 B / saturate to endpoint B
    ELSE                               // 参数在域内或贴 0 侧 / the parameter inside or at the lower edge
        FC_DL_LerpClamped := fA;       // 饱和到端点 A / saturate to endpoint A
    END_IF
    eErr   := 16#0002_0112;            // 信息级：结果非有限已饱和 / info level: the result was saturated
    bError := FALSE;                   // 信息级不置故障（R45）/ info level never raises the fault flag
    bValid := TRUE;                    // 端点值可用 / the endpoint value is usable
    RETURN;                            // 出口 / exit
END_IF

// 段 5｜域内正常出口 / segment 5, the in-domain outlet
FC_DL_LerpClamped := _fY;              // 域内插值结果 / the in-domain interpolation result
bError := FALSE;                       // 本路径无故障 / no fault on this path
bValid := TRUE;                        // 结果可用 / the result is usable
END_FUNCTION
