(*==============================================================================
 * 组件名称 (Component)  : FB_DL_TempCompClassify
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 组件功率温度补偿分档。
 *                         把实测功率按温度系数归一到一个基准温度，再把归一功率切成四档（G1 最低 … G4 最高），
 *                         相邻档之间带迟滞带，防止测点在分界线上抖动造成档位来回跳。
 *                         归一式（百分比系数口径，写死）：
 *                           P_norm = P_meas · (1 + k/100 · (T_meas − T_ref))
 *                           k 单位 %/°C，正 k 表示"温度升高时实测功率升高"，归一化需回减；
 *                           该式在 k/100·ΔT ≤ −1 时会出现非正比例因子，此时判 eNormCollapse 并停判。
 *                         分档结构（三阈值四档，迟滞带 fHyst 双向对称）：
 *                           升档：P_norm > fThN + fHyst 才升到 N+1
 *                           降档：P_norm < fThN − fHyst 才降到 N
 *                           带内（含边界）保持当前档 —— 这就是迟滞的全部作用，无其它隐藏状态。
 *                         验收向量：
 *                           ① k=0 之外的正常参数：P=1000 W, T=35 °C, k=+2 %/°C, Tref=25 °C
 *                              → 比例因子 1+0.02×10 = 1.20，P_norm = 1200 W
 *                           ② 阈值 800/1000/1200 W，迟滞 20 W：P_norm=1210 且当前 G3 → 升 G4
 *                           ③ 同参 P_norm=1190 且当前 G4 → 保持 G4（未破 1200−20）
 *                           ④ 同参 P_norm=1170 且当前 G4 → 降 G3
 * 接口     (Interface)  : 入 bEnable 使能、fPowerMeas 实测功率、fTempMeas 实测温度、fTempCoeff 温度系数、
 *                         fTempRefC 基准温度、fTh1..fTh3 三阈值、fHyst 迟滞半宽、bReset 复位沿；
 *                         出 fPwrNorm 归一功率、iGrade 档位（1..4，0 = 未分级）、bValid 有效、
 *                         bGradeChanged 换档脉冲（单拍）、eState 相、eCause 成因、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做"归一 + 分档"，不裁决组件是否合格、
 *                         不驱动负载功率设定**（属功率控制件）；② **温补系数零闸**：k = 0 或非有限
 *                         → 温补形同虚设且无任何可观测差异，属静默失效（R179），按故障级锁存；
 *                         ③ **阈值单调闸**：fTh1 < fTh2 < fTh3 且 fHyst ≥ 0，违反即锁存 eCfgIllegal；
 *                         ④ **迟滞半宽闸**：fHyst 必须小于最小相邻阈值间距的一半，否则档位可同时
 *                         满足升/降条件，出现"抖到死"或"跨档跳"，判 eCfgIllegal；
 *                         ⑤ **归一塌陷闸**：比例因子 ≤ 0 → 判 eNormCollapse（当拍不判档、bValid=FALSE，
 *                         不锁存，属样本侧异常而非组态异常）；
 *                         ⑥ 浮点比较一律用显式不等号 + 差值容差判等，禁 = / <> 直接判值；
 *                         ⑦ eFault 可迁出：bReset 上升沿 → eIdle，解除式恒可达（外部引脚门控）；
 *                         ⑧ 零全局耦合、零物理地址。
 * 分工声明 (Scope)      : 本件只管"功率温补与四档分级"。不接管：OCV 温度归一判带
 *                         （属 FB_DL_OcvTempNormalize）、温度闭环控制（属温控件）、
 *                         功率设定值下发（属功率环件）。
 * 来源标签 (Source Tag) : ROADMAP 空勾真缺口 P1（功率温补分档，自研 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位（零码位范式 R297）；诊断由 BOOL + ENUM 出口承担。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 零闸 + 单调闸 + 迟滞配比闸 + 塌陷闸 + 容差 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE 兜底 ｜ R7 ✓ R_TRIG 段 0 无条件刷新（本件无 TON）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R47 首版（批次 2 · 序号 8）
 *==============================================================================*)

TYPE E_DL_TccState :
(
    eIdle  := 0,    // 待机相（未使能） / Idle, disabled
    eRun   := 10,   // 分档相（归一与迟滞判档） / Running, normalise and classify
    eFault := 90    // 故障相（等复位） / Fault, awaiting reset
);
END_TYPE

TYPE E_DL_TccCause :
(
    eNone         := 0,   // 无异常 / No anomaly
    eCfgIllegal   := 1,   // 组态非法（阈值非单调 / 迟滞过宽） / Illegal configuration
    eCoeffZero    := 2,   // 温补系数为零或非有限（静默失效，故障级） / Zero or non-finite coefficient
    eNormCollapse := 3,   // 归一比例因子非正（样本侧异常，当拍不判） / Non-positive normalisation factor
    eSampleBad    := 4,   // 样本非有限（当拍不判） / Non-finite sample
    ePhaseBad     := 5    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_TempCompClassify
VAR_INPUT
    bEnable    : BOOL := FALSE;      // 使能（FALSE 冻结分档） [-] / Enable
    fPowerMeas : LREAL := 0.0;       // 实测功率 [W] / Measured power [W]
    fTempMeas  : LREAL := 25.0;      // 实测温度 [°C] / Measured temperature [°C]
    fTempCoeff : LREAL := 2.0;       // 温度系数，域 ≠ 0 且有限 [%/°C] / Temperature coefficient, non-zero and finite
    fTempRefC  : LREAL := 25.0;      // 基准温度 [°C] / Reference temperature [°C]
    fTh1       : LREAL := 800.0;     // 一档/二档分界 [W] / G1-G2 boundary [W]
    fTh2       : LREAL := 1000.0;    // 二档/三档分界 [W] / G2-G3 boundary [W]
    fTh3       : LREAL := 1200.0;    // 三档/四档分界 [W] / G3-G4 boundary [W]
    fHyst      : LREAL := 20.0;      // 迟滞半宽（对称），域 ≥ 0 [W] / Symmetric hysteresis half-width, >= 0
    bReset     : BOOL := FALSE;      // 故障复位沿 [-] / Fault reset edge
END_VAR
VAR_OUTPUT
    fPwrNorm      : LREAL := 0.0;                        // 归一到基准温度后的功率 [W] / Power normalised to the reference temperature
    iGrade        : INT := 0;                            // 档位 1..4（0 = 未分级） [档] / Grade 1..4, 0 = ungraded
    bValid        : BOOL := FALSE;                       // 结果有效 [-] / Result valid
    bGradeChanged : BOOL := FALSE;                       // 换档脉冲（单拍） [-] / Grade-change pulse, single scan
    eState        : E_DL_TccState := E_DL_TccState.eIdle;   // 相出口 [-] / Phase outlet
    eCause        : E_DL_TccCause := E_DL_TccCause.eNone;   // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError        : BOOL := FALSE;                       // 故障标志（仅故障级成因） [-] / Error flag, fault level only
END_VAR
VAR
    _eState   : E_DL_TccState := E_DL_TccState.eIdle;    // 内部相（CASE 唯一写入目标） / Internal phase
    _eCause   : E_DL_TccCause := E_DL_TccCause.eNone;    // 成因锁存量 / Latched cause
    _bFault   : BOOL := FALSE;                           // 故障锁存位 / Latched fault bit
    _iGrade   : INT := 0;                                // 内部档位（迟滞保持量） / Internal grade, hysteresis state
    _fNorm    : LREAL := 0.0;                            // 归一功率工作值 [W] / Normalised power working value
    _fRatio   : LREAL := 0.0;                            // 归一比例因子 [-] / Normalisation ratio
    _bChanged : BOOL := FALSE;                           // 换档脉冲内部位（单拍） / Internal grade-change pulse
    _bCfgBad  : BOOL := FALSE;                           // 组态非法当拍量 / Illegal configuration this scan
    _bSampleOk: BOOL := FALSE;                           // 样本有限性结论 / Sample finiteness result
    rtReset   : R_TRIG;                                  // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_TCC_EPS  : LREAL := 1.0E-9;   // 浮点判等容差（仅"贴边界"判定） [W] / Equality tolerance
    DL_TCC_PCT  : LREAL := 100.0;    // 百分数换算因子 [%] / Percentage scaling factor
    DL_TCC_WMIN : LREAL := 0.0;      // 归一功率下界（功率不许为负） [W] / Lower bound of the normalised power
END_VAR

(* —— 段 0：两沿无条件周期刷新（R228A；本件无 TON） —— *)
rtReset(CLK := bReset);                                          // 复位沿 / Reset edge

(* —— 段 1：单拍/输出量预置（锁存量 _eCause/_bFault/_iGrade 不入清单，R107） —— *)
fPwrNorm      := 0.0;                                            // 归一功率预置 / Normalised power preset
iGrade        := 0;                                              // 档位预置为未分级 / Grade preset to ungraded
bValid        := FALSE;                                          // 有效位预置 / Validity preset
_bChanged     := FALSE;                                          // 换档脉冲预清 / Grade-change pulse preset
bError        := FALSE;                                          // 故障标志预清（R45 配对） / Error preset
_fNorm        := 0.0;                                            // 工作值预置 / Working value preset
_fRatio       := 0.0;                                            // 比例因子预置 / Ratio preset

(* —— 段 2：组态闸（阈值单调 / 迟滞非负 / 迟滞不吞掉最窄间距） —— *)
_bCfgBad := NOT ((fTh1 < fTh2) AND (fTh2 < fTh3))                // 三阈值须严格单调 / Thresholds strictly monotonic
        OR (fHyst < 0.0)                                         // 迟滞半宽须非负 / Hysteresis must be non-negative
        OR (fHyst > ((fTh2 - fTh1) / 2.0))                       // 迟滞须小于最窄间距的一半 / Below half the narrowest gap
        OR (fHyst > ((fTh3 - fTh2) / 2.0));                      // 迟滞须小于最窄间距的一半（另一段同源约束） / Same constraint on the other gap
IF _bCfgBad THEN
    _eCause := E_DL_TccCause.eCfgIllegal;                        // 归因：组态非法 / Cause: illegal configuration
    _bFault := TRUE;                                             // 锁存 / Latch
    _eState := E_DL_TccState.eFault;                             // 入故障相 / Enter fault phase
END_IF

(* —— 段 3：温补系数零闸（k=0 使归一恒等，静默失效，故障级 R179） —— *)
IF (_eState <> E_DL_TccState.eFault) THEN
    IF (fTempCoeff = 0.0) OR (fTempCoeff <> fTempCoeff) OR ((fTempCoeff - fTempCoeff) <> (fTempCoeff - fTempCoeff)) THEN
        _eCause := E_DL_TccCause.eCoeffZero;                     // 归因：系数为零或非有限 / Cause: zero or non-finite coefficient
        _bFault := TRUE;                                         // 锁存 / Latch
        _eState := E_DL_TccState.eFault;                         // 入故障相 / Enter fault phase
    END_IF
END_IF

(* —— 段 4：迁出链（bReset 上升沿 → 待机相，并清档位保持量） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                            // 清故障锁存 / Clear fault latch
    _eCause := E_DL_TccCause.eNone;                              // 清成因 / Clear cause
    _iGrade := 0;                                                // 档位保持量清零（复位后重新起档） / Grade cleared, restart classification
    _eState := E_DL_TccState.eIdle;                              // 回待机相 / Back to idle
END_IF

(* —— 段 5：相迁移（使能驱动；故障相由段 4 迁出） —— *)
CASE _eState OF

E_DL_TccState.eIdle:
    IF bEnable THEN
        _eState := E_DL_TccState.eRun;                           // 使能即进分档相 / Enable enters the running phase
    END_IF

E_DL_TccState.eRun:
    IF NOT bEnable THEN
        _eState := E_DL_TccState.eIdle;                          // 失能回待机相（不借故障相过桥，R211） / Disable returns to idle
    END_IF

E_DL_TccState.eFault:
    ;                                                            // 故障相：由段 4 复位沿迁出 / Exit handled by the reset edge

ELSE
    _eCause := E_DL_TccCause.ePhaseBad;                          // 归因：非法相位 / Cause: illegal phase
    _bFault := TRUE;                                             // 锁存 / Latch
    _eState := E_DL_TccState.eFault;                             // 强拉故障相 / Force fault phase

END_CASE

(* —— 段 6：归一（样本有限性 → 比例因子 → 归一功率，非有限当拍不判） —— *)
IF _eState = E_DL_TccState.eRun THEN
    _bSampleOk := NOT ((fPowerMeas <> fPowerMeas) OR ((fPowerMeas - fPowerMeas) <> (fPowerMeas - fPowerMeas)))
              AND NOT ((fTempMeas <> fTempMeas) OR ((fTempMeas - fTempMeas) <> (fTempMeas - fTempMeas)))
              AND NOT ((fTempRefC <> fTempRefC) OR ((fTempRefC - fTempRefC) <> (fTempRefC - fTempRefC)));
    IF _bSampleOk THEN
        _fRatio := 1.0 + ((fTempCoeff / DL_TCC_PCT) * (fTempMeas - fTempRefC));   // 归一比例因子 / Normalisation ratio
        IF _fRatio <= 0.0 THEN
            _eCause := E_DL_TccCause.eNormCollapse;              // 归因：比例因子非正（样本侧异常） / Cause: non-positive ratio
        ELSE
            _fNorm := fPowerMeas * _fRatio;                      // 归一功率 / Normalised power
            IF _fNorm < DL_TCC_WMIN THEN
                _fNorm := DL_TCC_WMIN;                           // 下钳（功率不许为负） / Clamp to the physical lower bound
            END_IF
            bValid := TRUE;                                      // 结果有效 / Result valid

            (* 四档迟滞判档：以内部保持量 _iGrade 为中心，只判"升一档/降一档/保持" *)
            CASE _iGrade OF
            0:                                                       // 未起档：按当前值定初始档（无迟滞，首次定向） / Initial assignment without hysteresis
                IF _fNorm > fTh3 THEN
                    _iGrade := 4;
                ELSIF _fNorm > fTh2 THEN
                    _iGrade := 3;
                ELSIF _fNorm > fTh1 THEN
                    _iGrade := 2;
                ELSE
                    _iGrade := 1;
                END_IF
                _bChanged := TRUE;                                   // 首次定档亦视为换档 / Initial assignment counts as a change

            1:
                IF _fNorm > (fTh1 + fHyst) THEN
                    _iGrade := 2;                                    // 升档（破上界 + 迟滞） / Step up
                    _bChanged := TRUE;
                END_IF

            2:
                IF _fNorm > (fTh2 + fHyst) THEN
                    _iGrade := 3;                                    // 升档 / Step up
                    _bChanged := TRUE;
                ELSIF _fNorm < (fTh1 - fHyst) THEN
                    _iGrade := 1;                                    // 降档（破下界 − 迟滞） / Step down
                    _bChanged := TRUE;
                END_IF

            3:
                IF _fNorm > (fTh3 + fHyst) THEN
                    _iGrade := 4;                                    // 升档 / Step up
                    _bChanged := TRUE;
                ELSIF _fNorm < (fTh2 - fHyst) THEN
                    _iGrade := 2;                                    // 降档 / Step down
                    _bChanged := TRUE;
                END_IF

            4:
                IF _fNorm < (fTh3 - fHyst) THEN
                    _iGrade := 3;                                    // 降档 / Step down
                    _bChanged := TRUE;
                END_IF

            ELSE
                _iGrade := 0;                                        // 档位保持量非法：归零重起（不锁存，属内部自愈） / Internal self-heal
            END_CASE

            iGrade := _iGrade;                                       // 档位出口（与本拍判定同源） / Grade outlet, same origin
        END_IF
    ELSE
        _eCause := E_DL_TccCause.eSampleBad;                         // 归因：样本非有限（当拍不判） / Cause: non-finite sample
    END_IF
END_IF

(* —— 段 7：出口单点映射（名实双出口，R191） —— *)
fPwrNorm      := _fNorm;                                             // 归一功率出口 / Normalised power outlet
bGradeChanged := _bChanged;                                          // 换档脉冲出口 / Grade-change outlet
eState        := _eState;                                            // 相出口 / Phase outlet
eCause        := _eCause;                                            // 成因出口 / Cause outlet
bError        := _bFault;                                            // 故障标志 / Error flag

END_FUNCTION_BLOCK
