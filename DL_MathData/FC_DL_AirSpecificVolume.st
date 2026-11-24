(*
    FC_DL_AirSpecificVolume —— 湿空气比容计算（m³/kg 干空气，焓湿图全参族补件）
    ------------------------------------------------------------------
    组件名称  : FC_DL_AirSpecificVolume
    分类      : DL_MathData / Psychrometrics
    前缀      : FC_DL_
    版本      : 1.0.1
    溯源      : 借鉴点 —— 焓湿图学（psychrometrics）公开物理公式链：理想气体
                分压定律 + Magnus-Tetens 饱和水汽压参数化 + 比容式
                v = Ra·T / (p − φ·p_ws·(1 − Ra/Rv))。
                本件只借鉴**公式结构与判据顺序**两项公开语义。
                clean-room 声明 —— 零代码行复制；饱和水汽压**复用调用既有属主
                FC_DL_VaporPressureSat（DL_Algo，常量单源防口径漂移），不内联
                不复制其公式常量；实现 / 引脚名 / 码位 100% 自有。
                许可证 —— 本件 MIT；来源标签 t1-2-oscat-building 仅按行为定义
                落件（EPL-2.0 合规，R25 先例），不包含其任何受版权保护的实现。
    平台      : 纯 IEC 61131-3，CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R71 构建轮 · 批 1 · 序号 2）
    ------------------------------------------------------------------
    功能说明  : 计算湿空气比容（每 kg **干空气**所占容积）：
                v = Ra·T_K / (p − φ·p_ws·(1 − Ra/Rv))，[m³/kg 干空气]；
                其中 T_K = fTempC + 273.15，p_ws 为饱和水汽压（经属主件取得），
                Ra = 287.05 J/(kg·K) 干空气气体常数，Rv = 461.5 J/(kg·K) 水汽
                气体常数（公开物理常数，本件头注释内单源声明）。
                判据链顺序：非有限闸 → 压力域闸 → 温度 / 湿度钳位照算 →
                属主件取 p_ws → 分母有效性闸（先判后除）→ 结果非有限 /
                下界饱和闸。
                分母物理意义：p 减去水汽分压中「等效干空气占据」的修正项
                φ·p_ws·(1 − Ra/Rv)（R45 口径判据注释）；分母 <= 0 即过饱和 /
                低压非法组合，比容无解，信息级早退输出 0.0 —— **除零面在分母，
                必须先判后除**（φ = 100% 且 p_ws 接近总压的高湿低压组合为
                典型触发工况）。
                非有限判据（R79）：NaN 用 x <> x 自反判，Inf 用 (x − x) <> 0
                差值自反判 + 幅值 1E30 上界筛查，禁用近似阈值。
                浮点判等禁用 =（红线 5）：温度 / 湿度域界比较一律用 < / >。
    错误码    : 16#0002_3760 入参非有限（NaN / Inf / 超幅值），返回 0.0 —— 故障级
                16#0002_3761 温度或相对湿度域外承诺段，已钳位照算 —— 信息级，
                            值可用，不置 bError（R45）
                16#0002_3762 总压低于承诺段下界（< 10 kPa），安全侧拒绝，返回 0.0
                            —— 故障级（低压属承诺段外硬边界，高压侧无上界闸，
                            由结果饱和闸兜底）
                16#0002_3763 分母非正（过饱和 / 低压无解），返回 0.0 —— 信息级，
                            输出不可用（bValid = FALSE）但不置 bError（R45）
                16#0002_3764 结果非有限或越上界 → 拒收输出 0.0（不可用）；
                            越下界 → 饱和至下界输出（可用）—— 信息级，不置 bError
    码位总账  : 16#0002_3760 用 ｜ 16#0002_3761 用 ｜ 16#0002_3762 用 ｜
                16#0002_3763 用 ｜ 16#0002_3764 用
    状态机    : N/A —— 纯函数无状态，无 CASE 可写，非法状态不可能出现
    边界与披露: 一 无定时器 / 无边沿实例 / 无数组下标，周期安全规则 N/A；
                二 零全局变量、零 VAR_EXTERNAL、零物理地址；
                三 域闸逐项点名（R272）：fTempC / fRelHum / fPressPa 三入参全部
                   纳入非有限闸；fTempC 承诺段 [−20, 80] ℃，域外钳位照算 +
                   信息级（低温干燥是合法工况，与属主件口径一致）；
                   fRelHum 承诺段 [0, 100] %，域外钳位照算 + 信息级；
                   fPressPa 下界 10 kPa 为硬边界（低于即拒绝），上界由结果
                   饱和闸兜底（超高压 → 比容趋小 → 下界饱和截获）；
                四 除法面两处均先判后除：分母闸（段 7）与结果饱和闸（段 9），
                   无裸除法暴露；
                五 常数属主声明：饱和水汽压 p_ws 唯一来自 FC_DL_VaporPressureSat
                   调用返回，本件零内联 Magnus 常量；若属主件返回故障级
                   （温度非有限已在本件前置闸拦截，属主件自身 EXP 上溢域在
                   本件承诺段外不可达），本件按信息级 3763 同路径拒绝；
                六 依赖声明：仅依赖 Standard.library（ABS / RETURN）与同库
                   FC_DL_VaporPressureSat（DL_Algo，只调用不修改）。
                七 段 5 属主件调用为全 6 形参完整回执（v1.0.1 补 bValid => _bPwsVld，
                   R381 / E032 编译合规）；bValid = FALSE 与既有 (NOT _bPwsOk) OR
                   _bPwsErr 路径合并判定——属主件在全部非早退路径 bValid 恒 TRUE
                   （ROUND_PLAN_R72 §3 实测），合并不改变任何输出行为。
    分工声明  : FC_DL_AirDensity（DL_Algo）输出湿空气**密度**（kg/m³ 湿空气），
                FC_DL_HumidityRatioCalc（DL_Algo）输出**含湿量**（kg 水汽/kg
                干空气），本件输出**每 kg 干空气的容积**（m³/kg 干空气）——
                三者物理量纲不同、互为倒数邻域但语义不同，互引边界，不互代。
    修订记录  : 2026-11-22 v1.0.0 首次入库（R71 构建轮 · 批 1 · 序号 2）
                2026-11-23 v1.0.1 R72 批 0 点修（R386 对账 + R381 首用）：段 5 属主件
                            调用补第 6 形参回执 bValid => _bPwsVld（局部变量名按
                            _bPws* 前缀族一致性裁定，战报原名 _bAsvOk 在计划 §3 留痕），
                            并入段 5 早退判据（行为无变更，契约完整性修复）；
                            不改引脚、不改码位、不改其他段行为。
*)
FUNCTION FC_DL_AirSpecificVolume : LREAL
VAR_INPUT
    fTempC    : LREAL;                     (* 空气温度，承诺段 [-20, 80] 摄氏度，域外钳位照算 / the air temperature, promise range -20..80 degC, clamped outside *)
    fRelHum   : LREAL;                     (* 相对湿度，承诺段 [0, 100] 百分比，域外钳位照算 / the relative humidity in percent, promise range 0..100, clamped outside *)
    fPressPa  : LREAL;                     (* 湿空气总压，[Pa]，须 >= 10000（10 kPa 承诺段下界）/ the total air pressure in Pa, must be >= 10000 *)
END_VAR
VAR_OUTPUT
    bValid    : BOOL;                      (* 返回值可用，故障级或无解路径为 FALSE / the return usable, FALSE on fault level or unsolvable path *)
    nInfoCode : UDINT;                     (* 信息 / 错误码，0 = 正常 / the info or error id, 0 = ok *)
    bError    : BOOL;                      (* 故障标志，仅故障级码置位（R45 配对）/ the fault flag, raised only on fault-level codes *)
END_VAR
VAR CONSTANT
    DL_ASV_FMAX  : LREAL := 1.0E30;        (* 非有限筛查幅值上限，[Pa 或 ℃ 或 %] / the finiteness screening cap *)
    DL_ASV_PMIN  : LREAL := 10000.0;       (* 总压承诺段下界 10 kPa，[Pa] / the pressure promise lower bound, 10 kPa *)
    DL_ASV_TMIN  : LREAL := -20.0;         (* 温度承诺段下界，[摄氏度] / the temperature promise lower bound *)
    DL_ASV_TMAX  : LREAL := 80.0;          (* 温度承诺段上界，[摄氏度] / the temperature promise upper bound *)
    DL_ASV_RHMIN : LREAL := 0.0;           (* 相对湿度承诺段下界，[百分比] / the humidity promise lower bound *)
    DL_ASV_RHMAX : LREAL := 100.0;         (* 相对湿度承诺段上界，[百分比] / the humidity promise upper bound *)
    DL_ASV_RA    : LREAL := 287.05;        (* 干空气气体常数，[J/(kg·K)] / the dry air gas constant *)
    DL_ASV_RV    : LREAL := 461.5;         (* 水汽气体常数，[J/(kg·K)] / the water vapor gas constant *)
    DL_ASV_T0K   : LREAL := 273.15;        (* 摄氏度到开尔文偏移，[K] / the Celsius to Kelvin offset *)
    DL_ASV_VMIN  : LREAL := 1.0E-6;        (* 比容下界饱和值，[m³/kg 干空气] / the specific volume lower saturation floor *)
    DL_ASV_VMAX  : LREAL := 1.0E6;         (* 比容上界筛查值，[m³/kg 干空气] / the specific volume upper screening cap *)
END_VAR
VAR
    _fRhEff   : LREAL;                     (* 钳位后的生效相对湿度（小数形式），[无量纲 0..1] / the effective clamped humidity as a fraction *)
    _fTk      : LREAL;                     (* 开尔文温度中间量，[K] / the Kelvin temperature temporary *)
    _fPws     : LREAL;                     (* 饱和水汽压（属主件返回），[Pa] / the saturation vapor pressure from the owner FC *)
    _bPwsOk   : BOOL;                      (* 属主件调用成功标志，[标志] / the owner FC call success flag *)
    _bPwsErr  : BOOL;                      (* 属主件故障级标志，[标志] / the owner FC fault flag *)
    _uPwsCode : UDINT;                     (* 属主件码位回执，[码] / the owner FC code receipt *)
    _bPwsClmp : BOOL;                      (* 属主件钳位回执，[标志] / the owner FC clamp receipt *)
    _bPwsVld  : BOOL;                      (* 属主件输出可用回执（v1.0.1 补，E032 全回执），[标志] / the owner FC outputs usable receipt *)
    _fDenom   : LREAL;                     (* 比容式分母，[Pa] / the specific volume denominator *)
    _fV       : LREAL;                     (* 比容原始结果，[m³/kg 干空气] / the raw specific volume result *)
END_VAR

// 段 1｜返回值与状态预置（统一出口预置，R256）/ segment 1, preset the return and the status
FC_DL_AirSpecificVolume := 0.0;            // 故障缺省返回零比容 / the fault default is zero specific volume
bValid    := FALSE;                        // 预置不可用，过闸后置位 / preset unusable, set TRUE after the gates
nInfoCode := 0;                            // 预置无错 / preset no error
bError    := FALSE;                        // 预置无故障 / preset no fault

// 段 2｜三入参非有限闸（NaN 自反判 + Inf 差值自反判 + 幅值上界，R272 逐项点名）/ segment 2, the finiteness gate
IF (fTempC <> fTempC) OR ((fTempC - fTempC) <> 0.0) OR (ABS(fTempC) > DL_ASV_FMAX) THEN
    nInfoCode := 16#0002_3760;             // 故障级：温度非有限 / fault level: the temperature non finite
    bError := TRUE;                        // R45 配对置故障标志 / paired with the fault flag
    bValid := FALSE;                       // 返回值不可用 / the return unusable
    RETURN;                                // 结构早退 / structural exit
END_IF
IF (fRelHum <> fRelHum) OR ((fRelHum - fRelHum) <> 0.0) OR (ABS(fRelHum) > DL_ASV_FMAX) THEN
    nInfoCode := 16#0002_3760;             // 故障级：湿度非有限 / fault level: the humidity non finite
    bError := TRUE;                        // R45 配对 / paired with the flag
    bValid := FALSE;                       // 返回值不可用 / unusable
    RETURN;                                // 结构早退 / exit
END_IF
IF (fPressPa <> fPressPa) OR ((fPressPa - fPressPa) <> 0.0) OR (ABS(fPressPa) > DL_ASV_FMAX) THEN
    nInfoCode := 16#0002_3760;             // 故障级：总压非有限 / fault level: the pressure non finite
    bError := TRUE;                        // R45 配对 / paired with the flag
    bValid := FALSE;                       // 返回值不可用 / unusable
    RETURN;                                // 结构早退 / exit
END_IF

// 段 3｜压力硬域闸：低于 10 kPa 承诺段下界，安全侧拒绝 / segment 3, the hard pressure gate
IF fPressPa < DL_ASV_PMIN THEN             // 低压越硬下界（拒绝方向，不做钳位照算）/ under the hard lower bound, refused
    nInfoCode := 16#0002_3762;             // 故障级：总压低于承诺段 / fault level: the pressure under the promise
    bError := TRUE;                        // R45 配对 / paired with the flag
    bValid := FALSE;                       // 返回值不可用 / unusable
    RETURN;                                // 结构早退 / exit
END_IF

// 段 4｜温度 / 湿度承诺段钳位照算（域外合法工况降级为趋势参考，信息级）/ segment 4, the promise-range clamp
_fRhEff := fRelHum / 100.0;                // 百分比转小数形式，[无量纲] / percent to fraction
IF (fTempC < DL_ASV_TMIN) OR (fTempC > DL_ASV_TMAX) OR (fRelHum < DL_ASV_RHMIN) OR (fRelHum > DL_ASV_RHMAX) THEN
    IF fTempC < DL_ASV_TMIN THEN           // 温度低于下界 / temperature under the lower bound
        _fTk := DL_ASV_TMIN + DL_ASV_T0K;  // 钳到承诺段下界换算开尔文 / clamp to the lower bound in Kelvin
    ELSIF fTempC > DL_ASV_TMAX THEN        // 温度高于上界 / temperature over the upper bound
        _fTk := DL_ASV_TMAX + DL_ASV_T0K;  // 钳到承诺段上界 / clamp to the upper bound
    ELSE                                   // 温度在段内 / the temperature inside
        _fTk := fTempC + DL_ASV_T0K;       // 原值换算开尔文 / the raw value to Kelvin
    END_IF
    IF _fRhEff < 0.0 THEN                  // 湿度小数低于 0 / the fraction under zero
        _fRhEff := 0.0;                    // 钳到 0（全干空气）/ clamp to zero, all dry air
    ELSIF _fRhEff > 1.0 THEN               // 湿度小数高于 1 / the fraction over one
        _fRhEff := 1.0;                    // 钳到 1（全饱和）/ clamp to one, fully saturated
    END_IF
    nInfoCode := 16#0002_3761;             // 信息级：域外承诺段已钳位照算 / info level: clamped outside the promise range
ELSE                                       // 温度湿度均在承诺段内 / both inside the promise range
    _fTk := fTempC + DL_ASV_T0K;           // 原值换算开尔文 / the raw value to Kelvin
END_IF

// 段 5｜饱和水汽压取值（属主件复用调用，常量单源，不内联 Magnus 常量）/ segment 5, the saturation pressure via the owner FC
_bPwsOk := FC_DL_VaporPressureSat(fTempC := (_fTk - DL_ASV_T0K),  // 换回摄氏度入参（承诺段内必在属主域 [-40,100] 内）/ back to Celsius, inside the owner domain
                                  fPvSat => _fPws,                // 饱和压出参回执 / the saturation pressure receipt
                                  bClamped => _bPwsClmp,          // 钳位回执（本段内恒 FALSE，收下备用）/ the clamp receipt
                                  eErr => _uPwsCode,              // 码位回执 / the code receipt
                                  bError => _bPwsErr,             // 故障回执 / the fault receipt
                                  bValid => _bPwsVld);            // 输出可用回执（v1.0.1 补齐第 6 形参，R381/E032）/ the outputs usable receipt
IF (NOT _bPwsOk) OR _bPwsErr OR (NOT _bPwsVld) THEN // 任一回执不可用即走 3763 信息级早退（v1.0.1 合并 bValid，行为无变更）/ any unusable receipt takes the info level early exit
    nInfoCode := 16#0002_3763;             // 信息级：饱和压不可得，同无解路径拒绝 / info level: no saturation pressure, refused
    bError := FALSE;                       // 信息级不置故障（R45）/ info level never raises the flag
    bValid := FALSE;                       // 返回值不可用 / unusable
    FC_DL_AirSpecificVolume := 0.0;        // 确定值零出口 / a deterministic zero outlet
    RETURN;                                // 结构早退 / exit
END_IF

// 段 6｜比容式分母组装（先组装后判，除法面在段 7 之后）/ segment 6, the denominator assembly
_fDenom := fPressPa - (_fRhEff * _fPws * (1.0 - DL_ASV_RA / DL_ASV_RV)); // 分母 = p − φ·p_ws·(1−Ra/Rv)，[Pa] / the denominator

// 段 7｜分母有效性闸（先判后除，R45；分母 <= 0 即过饱和 / 低压无解）/ segment 7, the denominator validity gate
IF _fDenom <= 0.0 THEN                     // 分母非正（水汽分压修正项吞没总压）/ the denominator non positive
    nInfoCode := 16#0002_3763;             // 信息级：过饱和 / 低压无解 / info level: supersaturated or unsolvable
    bError := FALSE;                       // 信息级不置故障（R45）/ info level never raises the flag
    bValid := FALSE;                       // 返回值不可用 / unusable
    FC_DL_AirSpecificVolume := 0.0;        // 确定值零出口（计划口径：早退出信息码、输出 0.0）/ a deterministic zero outlet
    RETURN;                                // 结构早退 / exit
END_IF

// 段 8｜比容主体：v = Ra·T_K / 分母（分母已过闸，仍防御性收口）/ segment 8, the specific volume kernel
_fV := DL_ASV_RA * _fTk / _fDenom;         // 比容原始结果，[m³/kg 干空气] / the raw specific volume

// 段 9｜结果非有限闸 + 上下界饱和（结果域收口，绝不送非有限值给下游）/ segment 9, the result finiteness and saturation gate
IF (_fV <> _fV) OR ((_fV - _fV) <> 0.0) OR (_fV > DL_ASV_VMAX) THEN
    nInfoCode := 16#0002_3764;             // 信息级：结果非有限或越上界 / info level: the result non finite or over the cap
    bError := FALSE;                       // 信息级不置故障（R45）/ info level never raises the flag
    bValid := FALSE;                       // 非有限结果不可用（越上界同样拒收，安全侧收紧）/ the non finite result unusable
    FC_DL_AirSpecificVolume := 0.0;        // 确定值零出口 / a deterministic zero outlet
    RETURN;                                // 结构早退 / exit
END_IF
IF _fV < DL_ASV_VMIN THEN                  // 结果低于下界（超高压工况，公式有效域外的防御截获）/ the result under the floor
    nInfoCode := 16#0002_3764;             // 信息级：结果已饱和至下界 / info level: saturated to the floor
    bError := FALSE;                       // 信息级不置故障 / never raises the flag
    bValid := TRUE;                        // 下界饱和值仍可用于下游限幅链路 / the floor value still usable
    FC_DL_AirSpecificVolume := DL_ASV_VMIN; // 饱和至下界出口 / the floor outlet
    RETURN;                                // 出口 / exit
END_IF

// 段 10｜域内正常出口 / segment 10, the in-domain outlet
FC_DL_AirSpecificVolume := _fV;            // 域内比容结果 / the in-domain specific volume
bValid := TRUE;                            // 结果可用 / the result usable
END_FUNCTION
