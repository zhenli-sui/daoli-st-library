(*==============================================================================
 * 组件名称 (Component)  : FB_DL_FuzzyTrim2In
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（ABS / MAX），零厂商私有库
 * 功能描述 (Function)   : 二输入模糊规则表修调（Mamdani 结构，结构只借、参数自组态）：
 *                         误差 fErr 与误差变化率 fErrRate（均已标幺 -1~1）各做 5 级三角
 *                         隶属度（NB/NS/Z/PS/PB，中心点 -1/-0.5/0/0.5/1，半宽 0.5，
 *                         VAR CONSTANT 可组态）；5×5=25 条规则以 ST_DL_ 常量二维数组落地
 *                         （单点输出集中心，域 [-1,1]）；重心法解模糊：
 *                           fTrim = fGainOut × Σ(w_i×c_i) / Σw_i （w_i = μe×μr）
 *                         适用非线性滞回对象（注塑保压、炉温搭接段）的 PID 外挂修调。
 * 接口     (Interface)  : 输入 fErr 误差（已标幺 -1~1）、fErrRate 误差变化率（已标幺 -1~1）、
 *                         fGainOut 输出增益（>=0）、bReset 复位；输出 fTrim 修调量
 *                         （-fGainOut~+fGainOut）、nRuleHit 命中规则数（诊断）、bNoRule
 *                         无有效规则、bError 组态故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做模糊查表与解模糊，不做标幺换算、
 *                         不接管主回路**；误差/变化率的标幺化由上层标幺件负责。
 *                         ② 输入先钳 [-1,1] 再做隶属度（超域输入不放大）。
 *                         ③ Σw_i 下限闸：Σw_i < 1E-6（全零隶属退化）→ fTrim=0 并置
 *                         bNoRule（防除零，R28）。
 *                         ④ 非有限输入 → 冻结输出（保持上拍 fTrim，不重算）。
 *                         ⑤ 规则表/中心表均为定界常量数组，循环索引为字面常量 0..4，
 *                         天然无越界路径（数组边界红线以静态定界满足）。
 *                         ⑥ 组态闸：fGainOut < 0 → 锁存 bError，输出 0 安全侧，解除沿 =
 *                         bReset 上升沿。
 *                         ⑦ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 分工声明 (Scope)      : 全库无 Fuzzy 族，本件开族；与 PID 族（CascadePid 等）分工：
 *                         模糊修调是非线性补正外挂 ≠ 主调节器。
 * 来源标签 (Source Tag) : T2-5 ◐（Mamdani 结构与重心法只借公开定义，5×5 规则表为本件
 *                         自组态参数域，零文本复制）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 LREAL 修调量 + BOOL/UDINT 组；
 *                         数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ Σw 下限闸 + 输入钳位 + 非有限冻结 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（查表无状态机） ｜ R7 ✓ 一 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R48 首版（批次 2 · 序号 8）
 *                         验收向量：e=-1,r=-1 → fTrim=-fGainOut；e=0,r=0 → 0；
 *                         中间值重心插值连续；fGainOut<0 → bError 锁存。
 *==============================================================================*)

TYPE E_DL_FzyTerm :
(
    eNB := 0,    // 负大隶属级 / Negative-big term
    eNS := 1,    // 负小隶属级 / Negative-small term
    eZ  := 2,    // 零隶属级 / Zero term
    ePS := 3,    // 正小隶属级 / Positive-small term
    ePB := 4     // 正大隶属级 / Positive-big term
);
END_TYPE

FUNCTION_BLOCK FB_DL_FuzzyTrim2In
VAR_INPUT
    fErr     : LREAL := 0.0;    // 误差输入（已标幺，域按 [-1,1] 使用，超域先钳） [-] / Error input, normalized
    fErrRate : LREAL := 0.0;    // 误差变化率输入（已标幺） [-] / Error-rate input, normalized
    fGainOut : LREAL := 10.0;   // 修调输出增益（域 >= 0） [工程单位] / Output gain
    bReset   : BOOL := FALSE;   // 复位，上升沿清组态故障锁存 [-] / Reset, rising edge clears config fault
END_VAR
VAR_OUTPUT
    fTrim    : LREAL;           // 模糊修调输出，域 [-fGainOut, +fGainOut] [工程单位] / Fuzzy trim output
    nRuleHit : UDINT;           // 命中规则数（w_i > 0 的规则条数，诊断用） [条] / Rule-hit count for diagnostics
    bNoRule  : BOOL;            // 无有效规则（Σw 过小，输出 0） [-] / No effective rule flag
    bError   : BOOL;            // 组态故障标志（锁存） [-] / Configuration fault flag, latched
END_VAR
VAR
    _fErrC   : LREAL;           // 当拍钳位后误差 [-] / Clamped error this scan
    _fRatC   : LREAL;           // 当拍钳位后误差变化率 [-] / Clamped error rate this scan
    _aMuE    : ARRAY[0..4] OF LREAL;   // 误差五级隶属度 [-] / Error membership grades
    _aMuR    : ARRAY[0..4] OF LREAL;   // 变化率五级隶属度 [-] / Rate membership grades
    _fSumW   : LREAL;           // Σw 累加中间量 [-] / Weight sum accumulator
    _fSumWC  : LREAL;           // Σ(w×c) 累加中间量 [-] / Weighted-center accumulator
    _nHit    : UDINT;           // 命中规则内部量 [条] / Rule-hit internal
    _fTrim   : LREAL := 0.0;    // 修调锁存镜像（冻结源） / Trim latch mirror, freeze source
    _bErrLatch : BOOL;          // 组态故障锁存位（解除沿 = bReset 上升沿） / Latched config fault, cleared by reset edge
    rtReset  : R_TRIG;          // 复位沿实例，段 0 无条件调用 / Reset edge instance
    _bNonFin : BOOL;            // 输入非有限当拍量 [-] / Non-finite input this scan
    i        : DINT;            // 规则表行索引（误差级） / Rule table row index
    j        : DINT;            // 规则表列索引（变化率级） / Rule table column index
    _fW      : LREAL;           // 单规则权重中间量 [-] / Single rule weight
END_VAR
VAR CONSTANT
    DL_FZY_HALF  : LREAL := 0.5;      // 三角隶属半宽（中心间隔相同） [-] / Triangle membership half-width
    DL_FZY_WMIN  : LREAL := 1.0E-6;   // Σw 下限闸（防除零） [-] / Weight-sum floor
    DL_FZY_ONE   : LREAL := 1.0;      // 单位常量（钳位上限） [-] / Unit constant
    DL_FZY_CEN   : ARRAY[0..4] OF LREAL := [-1.0, -0.5, 0.0, 0.5, 1.0];   // 五级隶属中心点（NB/NS/Z/PS/PB），组态参数域 [-] / Five membership centers
    DL_FZY_RULE  : ARRAY[0..4, 0..4] OF LREAL := [   // 5×5 规则表：行=误差级、列=变化率级 [-] / 5x5 rule table of singleton centers
        -1.0, -1.0, -0.5, -0.5,  0.0,
        -1.0, -0.5, -0.5,  0.0,  0.5,
        -0.5, -0.5,  0.0,  0.5,  0.5,
        -0.5,  0.0,  0.5,  0.5,  1.0,
         0.0,  0.5,  0.5,  1.0,  1.0];
                                      // 5×5 规则表：行=误差级、列=变化率级，值为单点输出集中心，对称反对角设计 [-] / 5x5 rule table of singleton centers
END_VAR

(* —— 段 0：非有限判 + 组态闸 + 输入钳位 + 沿刷新 —— *)
_bNonFin := (fErr <> fErr) OR ((fErr - fErr) <> 0.0)
         OR (fErrRate <> fErrRate) OR ((fErrRate - fErrRate) <> 0.0);   // 输入非有限（R245） / Non-finite input tests
IF fGainOut < 0.0 THEN
    _bErrLatch := TRUE;                                   // 增益负值组态闸：锁存（R188 解除沿 = bReset 上升沿） / Negative gain gate: latch
END_IF
rtReset(CLK := bReset);                                   // 复位沿，每拍必调 / Reset edge, every scan

(* —— 段 1：复位沿 —— *)
IF rtReset.Q THEN
    _bErrLatch := FALSE;                                  // 清组态故障锁存 / Clear config fault latch
END_IF

(* —— 段 2：隶属度与解模糊（非有限冻结；故障期安全侧） —— *)
nRuleHit := 0;                                            // 命中数出口预清 / Hit count preset
bNoRule  := FALSE;                                        // 无规则标志预清 / No-rule flag preset
IF _bErrLatch THEN
    _fTrim := 0.0;                                        // 故障安全侧：修调归零 / Fault safe side: zero trim
ELSIF _bNonFin THEN
    (* 非有限输入：冻结上拍 _fTrim 不重算（头注释④） *)
    ;                                                     // 冻结分支保持 / Freeze branch holds
ELSE
    IF fErr > DL_FZY_ONE THEN
        _fErrC := DL_FZY_ONE;                             // 误差上钳 [-1,1] / Clamp error high
    ELSIF fErr < -DL_FZY_ONE THEN
        _fErrC := -DL_FZY_ONE;                            // 误差下钳 / Clamp error low
    ELSE
        _fErrC := fErr;                                   // 域内直通 / In-domain pass
    END_IF
    IF fErrRate > DL_FZY_ONE THEN
        _fRatC := DL_FZY_ONE;                             // 变化率上钳 / Clamp rate high
    ELSIF fErrRate < -DL_FZY_ONE THEN
        _fRatC := -DL_FZY_ONE;                            // 变化率下钳 / Clamp rate low
    ELSE
        _fRatC := fErrRate;                               // 域内直通 / In-domain pass
    END_IF
    FOR i := 0 TO 4 DO
        IF (_fErrC - DL_FZY_CEN[i]) < 0.0 THEN
            _aMuE[i] := DL_FZY_HALF + (_fErrC - DL_FZY_CEN[i]);   // 左斜坡隶属（三角左半）/ Left ramp membership
        ELSE
            _aMuE[i] := DL_FZY_HALF - (_fErrC - DL_FZY_CEN[i]);   // 右斜坡隶属（三角右半）/ Right ramp membership
        END_IF
        IF _aMuE[i] < 0.0 THEN
            _aMuE[i] := 0.0;                              // 负隶属截零 / Clamp membership to zero
        END_IF
        IF (_fRatC - DL_FZY_CEN[i]) < 0.0 THEN
            _aMuR[i] := DL_FZY_HALF + (_fRatC - DL_FZY_CEN[i]);   // 变化率左斜坡 / Rate left ramp
        ELSE
            _aMuR[i] := DL_FZY_HALF - (_fRatC - DL_FZY_CEN[i]);   // 变化率右斜坡 / Rate right ramp
        END_IF
        IF _aMuR[i] < 0.0 THEN
            _aMuR[i] := 0.0;                              // 负隶属截零 / Clamp membership to zero
        END_IF
    END_FOR
    _fSumW  := 0.0;                                       // Σw 清零 / Clear weight sum
    _fSumWC := 0.0;                                       // Σ(w×c) 清零 / Clear weighted center
    _nHit   := 0;                                         // 命中数清零 / Clear hit count
    FOR i := 0 TO 4 DO
        FOR j := 0 TO 4 DO
            _fW := _aMuE[i] * _aMuR[j];                   // 单规则权重 = μe×μr / Single rule weight
            IF _fW > 0.0 THEN
                _fSumW  := _fSumW + _fW;                  // 累加权重 / Accumulate weight
                _fSumWC := _fSumWC + _fW * DL_FZY_RULE[i][j];   // 累加权重×中心 / Accumulate weight times center
                _nHit := _nHit + 1;                       // 命中规则计数 / Count hit rule
            END_IF
        END_FOR
    END_FOR
    IF _fSumW < DL_FZY_WMIN THEN
        _fTrim := 0.0;                                    // Σw 下限闸：全零隶属退化输出 0（R28 防除零） / Weight-sum floor: zero output
        bNoRule := TRUE;                                  // 置无有效规则标志 / Raise no-rule flag
        _nHit := 0;                                       // 无有效规则命中数归零 / Zero hit count
    ELSE
        _fTrim := fGainOut * _fSumWC / _fSumW;            // 重心法解模糊（分母已过闸） / Centre-of-gravity defuzzification
    END_IF
END_IF

(* —— 段 3：出口单点映射（名实双出口同源，R191） —— *)
fTrim    := _fTrim;                                       // 修调出口 / Trim outlet
nRuleHit := _nHit;                                        // 命中数出口 / Hit count outlet
bError   := _bErrLatch;                                   // 故障标志出口 / Error flag outlet

END_FUNCTION_BLOCK
