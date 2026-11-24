(*
  ==================================================================
  组件名 Component  : FB_DL_EwmaFilter
  分类   Category   : DL_Algo
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0002_373B / 373C（故障级）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 低
  功能   Purpose    : EWMA 指数加权滑动平均 fOut := fOut + α×(fIn − fOut)，α 直接
                      入参（离散统计 / SPC 平滑口径），供调用方直接整定平滑系数。
  开源溯源 Origin    : 公开公式 clean-room，参考公开统计过程控制（SPC）教材的
                      EWMA 定义（分类与公式借鉴，零代码复制），本件实现、闸门与
                      码位 100% 自有。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6 算术运算符；EWMA 递推式 y[k] =
                      y[k−1] + α·(x[k] − y[k−1]) 为公开统计公式
  平台   Platform   : 纯 IEC 61131-3（四则 / 比较），三平台通用
  依赖   Depends    : 仅 Standard.library（无库调用、无定时器）
  分工声明 Split     : FB_DL_LowPassFilter 为连续时间常数口径（α 由 tTf / tDt 派生，
                      一阶 RC 语义）；FB_DL_MovingAverage 为等权滑窗；本件为调用方
                      直接给 α 的统计平滑口径（EWMA / SPC 语义）；三者选型对照进
                      MANUAL_DL_Algo（R216 双向互引）。
  归属 Ownership     : 本件无 TYPE 声明；全部引脚为 IEC 标准原生类型。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 α 域闸 (0, 1]：fAlpha <= 0 或 > 1 或非有限 → 组态码 373B +
                         出口三件套 + RETURN 结构早退（开区间下界防输出冻结，
                         α = 0 是「禁冻结伪装正常」的组态错误而非合法参数）；
                      二 fIn 非有限（NaN / ±Inf）→ 本拍拒绝更新、保持上拍有效值 +
                         故障码 373C + 三件套（禁污染物进入递推状态）；
                      三 首拍 _bInit → fOut := fIn 首样本直通（禁输出 0 假跳变）；
                      四 bEnable = FALSE 的语义写死（FB33-4 声明行）：本件取「冻结
                         最后有效值」，理由：纯监视滤波不驱动功率级，冻结均值供
                         HMI 连续读数（与 BiquadFilter 的「控制量归零」口径不同，
                         选型时注意）；
                      五 故障码策略（本件无 bReset 引脚，R152 解除路径自证）：组态类
                         与测量类故障码逐拍重算不锁存，解除路径 = 修正组态 / 恢复
                         测点（恒可达）；首因保序由判据顺序保证；
                      六 非有限闸逐个点名（R272）：fAlpha 与 fIn 双双入闸；
                      七 首拍 _bInit 全量初始化（FB50-2）；无定时器 / 无边沿实例，
                         段 0 无刷新对象（R6 标注 N/A）；无全局、无外部变量、无
                         物理地址、无指针。
  错误码 Codes      :
    16#0002_373B【故障级】组态非法（fAlpha ≤ 0 / > 1 / 非有限）
    16#0002_373C【故障级】输入非有限（fIn 为 NaN / ±Inf）或递推结果非有限（后者
                         理论上不可达的兜底分支，与输入坏同码，出口组合不可区分，
                         R90 反证：fOut 保持上拍有效值 + bValid = FALSE 两场景同形）
  码位反证 Note     :
    373B 与 373C 不可合并：两者的处置人不同（组态工程师调 α / 仪表工查测点），
    而两者出口组合不同（组态坏无论 fIn 有限与否恒发 373B），可由场景唯一还原，
    故分立两码（R90）。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 α = 1 → 直通 fOut = fIn（逐拍断言）
    V2 α = 0 → 码 373B + 三件套 + 早退（禁冻结伪装正常）
    V3 α = 0.5 阶跃 0 → 100 → 逐拍 50 / 75 / 87.5 收敛，无超调
    V4 fIn = NaN → 保持上拍 fOut + 码 373C + bValid = FALSE
    V5 首拍 → fOut = fIn 首样本直通（禁 0 假跳变）
    V6 bEnable = FALSE → fOut 冻结最后有效值（边界四声明行回归向量）
  修订记录 Revision  :
    2026-11-21  v1.0.0  R63 首版（批 1 · 序号 3）
  ==================================================================
*)
FUNCTION_BLOCK FB_DL_EwmaFilter
VAR_INPUT
    bEnable  : BOOL := TRUE;  // 使能，FALSE 时输出冻结最后有效值（边界四）/ the enable, false freezes the last valid output
    fIn      : LREAL := 0.0;  // 输入量 [工程单位]，必须有限 / the input value, must be finite
    fAlpha   : LREAL := 0.2;  // 平滑系数 [−]，合法域 (0, 1] 开区间下界 / the smoothing factor inside the half open domain from zero exclusive to one
END_VAR
VAR_OUTPUT
    fOut     : LREAL := 0.0;           // 滤波输出 [工程单位] / the filtered output
    bValid   : BOOL := FALSE;          // 输出可用（使能 + 无故障 + 首样本已收）[-] / the output is usable
    eErr     : UDINT := 16#0000_0000;  // 错误码，0 = 正常 / the error code, zero is ok
    bError   : BOOL := FALSE;          // 故障标志（故障级码同拍置位，R45 配对）/ the fault flag raised with a fault level code
END_VAR
VAR
    _bInit    : BOOL := FALSE;   // 首拍初始化标志（R310 / FB50-2）/ the first scan flag
    _bHasSamp : BOOL := FALSE;   // 已收首样本标志（跨拍保持）/ the first sample received flag
    _fOutLast : LREAL := 0.0;    // 最近一次有效输出（冻结与递推基线）[工程单位] / the last valid output used as the freeze and the recursion base
    _bFinIn   : BOOL := FALSE;   // 输入有限闸结果（逐拍重算）/ the input finiteness gate result
    _bFinAlp  : BOOL := FALSE;   // 平滑系数有限闸结果（逐拍重算）/ the alpha finiteness gate result
END_VAR  // R64 结构补齐：VAR 段缺失的 END_VAR（门禁机械修复）
VAR CONSTANT
    DL_EWM_ZERO : LREAL := 0.0; // 实数零常量 [工程单位] / the real zero constant
    DL_EWM_ONE  : LREAL := 1.0; // 实数一常量（α 上界）[-] / the real unit constant, the alpha ceiling
END_VAR

// 段 0｜本件无定时器与边沿实例（纯递推滤波器，R6 标注 N/A），无刷新对象 / segment 0, no timers and no edge instances exist here

// 段 1｜首拍初始化（FB50-2）/ segment 1, the first scan init
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _bHasSamp := FALSE; // 首样本标志显式清零（触发首拍直通）/ clear the first sample flag so the direct pass triggers
    _fOutLast := DL_EWM_ZERO; // 最近有效输出显式清零 / clear the last valid output explicitly
END_IF

// 段 2｜非有限闸逐个点名（R272：fAlpha 与 fIn 双双入闸）/ segment 2, the finiteness gates naming both real pins
_bFinAlp := (fAlpha = fAlpha) AND ((fAlpha - fAlpha) = (fAlpha - fAlpha)); // 平滑系数有限 / the alpha is finite
_bFinIn := (fIn = fIn) AND ((fIn - fIn) = (fIn - fIn)); // 输入有限 / the input is finite

// 段 3｜α 组态域闸：结构早退（边界一，出口三件套 + RETURN）/ segment 3, the alpha domain gate with the structural early exit
IF (NOT _bFinAlp) OR (fAlpha <= DL_EWM_ZERO) OR (fAlpha > DL_EWM_ONE) THEN // 组态非法 / an illegal configuration
    fOut := _fOutLast; // 出口保持最近有效值（禁自赋值出口，R261）/ keep the last valid output instead of a self assignment
    bValid := FALSE; // 输出不可用 / the output is not usable
    eErr := 16#0002_373B; // 故障级：α 组态非法 / fault grade, the alpha configuration is illegal
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    RETURN; // 早退（组态非法结构早退，R1 同族口径）/ early return, the structural exit on an illegal configuration
END_IF

// 段 4｜失能分支：冻结最后有效值（边界四声明行）/ segment 4, the disabled branch freezes the last valid output
IF NOT bEnable THEN // 失能 / disabled
    fOut := _fOutLast; // 冻结最后有效值（纯监视滤波，理由见边界四）/ freeze the last valid output, a pure monitoring filter
    bValid := FALSE; // 失能即不可用 / the output is not usable while disabled
    bError := FALSE; // 失能不是故障 / a disabled device is not a fault
    eErr := 16#0000_0000; // 失能不发码 / no code is emitted while disabled
    RETURN; // 早退，不推进递推 / early return without advancing the recursion
END_IF

// 段 5｜输入非有限：拒绝更新并保持（边界二，禁污染物进状态）/ segment 5, a non finite input is rejected
IF NOT _bFinIn THEN // 输入坏 / the input is broken
    fOut := _fOutLast; // 保持上拍有效值 [工程单位] / keep the last valid output
    bValid := FALSE; // 输出不可用 / the output is not usable
    eErr := 16#0002_373C; // 故障级：输入非有限 / fault grade, the input is not finite
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    RETURN; // 早退，递推状态不被污染 / early return, the recursion state stays clean
END_IF

// 段 6｜首样本直通（边界三，禁 0 假跳变）/ segment 6, the first sample passes straight through
IF NOT _bHasSamp THEN // 尚无首样本 / no first sample yet
    _fOutLast := fIn; // 基线 = 首样本 [工程单位] / the base is the first sample
    _bHasSamp := TRUE; // 置首样本标志 / raise the first sample flag
    fOut := fIn; // 首拍直通 [工程单位] / the first scan passes straight through
    bValid := TRUE; // 输出可用 / the output is usable
    eErr := 16#0000_0000; // 正常 / ok
    bError := FALSE; // 无故障 / no fault
    RETURN; // 早退 / early return
END_IF

// 段 7｜EWMA 递推（公开公式）：fOut = fOutLast + α×(fIn − fOutLast) / segment 7, the EWMA recursion
fOut := _fOutLast + (fAlpha * (fIn - _fOutLast)); // 指数加权滑动平均 [工程单位] / the exponentially weighted moving average

// 段 8｜递推结果非有限兜底（三件套，R258；与输入坏同码，反证见码表）/ segment 8, the non finite result fallback
IF (fOut <> fOut) OR ((fOut - fOut) <> (fOut - fOut)) THEN // 结果非有限（NaN 自反 / Inf 差值自减）/ a non finite result tested by reflexivity and the self difference
    fOut := _fOutLast; // 回退保持上拍有效值 [工程单位] / fall back to the last valid output
    bValid := FALSE; // 输出不可用 / the output is not usable
    eErr := 16#0002_373C; // 故障级：输入或结果非有限（同族一码）/ fault grade, the input or the result is not finite
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    RETURN; // 早退，基线不被污染 / early return, the base stays clean
END_IF

// 段 9｜统一出口（基线推进 + 可用声明）/ segment 9, the unified outlet
_fOutLast := fOut; // 基线推进（写前已过非有限闸）[工程单位] / advance the base after the finiteness gate
bValid := TRUE; // 输出可用 / the output is usable
bError := FALSE; // 无故障 / no fault
eErr := 16#0000_0000; // 正常 / ok
END_FUNCTION_BLOCK
