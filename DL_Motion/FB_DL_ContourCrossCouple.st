(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ContourCrossCouple
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（ABS / SQRT / MAX），零厂商私有库
 * 功能描述 (Function)   : 双轴轮廓交叉耦合控制（闭环修调侧）：由两轴跟随误差合成轮廓误差
 *                           fEc = (fErrX×fDirX + fErrY×fDirY) / SQRT(fDirX²+fDirY²)
 *                         （fDirX/fDirY 为轨迹方向单位向量分量，组态输入），再把轮廓误差
 *                         垂直分量还给弱轴：
 *                           fTrimY = +fKc × fEc × fDirX
 *                           fTrimX = -fKc × fEc × fDirY
 *                         输出限幅 ±fTrimMaxMm；bEnable 退出时修调斜坡归零（禁突跳）；
 *                         使能期输出同样按 fRampMmS 斜率逼近目标值（换段方向向量突变
 *                         不产生阶跃）。
 * 接口     (Interface)  : 输入 fErrX/fErrY 两轴跟随误差（mm）、fDirX/fDirY 轨迹方向向量
 *                         分量（无量纲）、fKc 交叉耦合增益（0~1）、fTrimMaxMm 修调限幅
 *                         （mm）、fRampMmS 修调变化率限（mm/s）、fCycle 扫描周期（s，
 *                         <=0 用缺省）、bEnable 使能、bReset 复位；输出 fTrimX/fTrimY
 *                         修调注入（mm）、bNoDir 方向向量退化、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只算修调注入量，不写轴位置指令、
 *                         不接管插补器**；注入点由上层叠加到从轴位置设定。
 *                         ② 方向向量模 < 1E-6 → 直通零修调并置 bNoDir（R28 防零，不开方
 *                         负数/除零）。
 *                         ③ 非有限误差冻结当拍斜坡目标（保持逼近上一目标，R245）。
 *                         ④ 斜坡归零：bEnable=FALSE 时目标=0，输出按 fRampMmS×fCycle 向 0
 *                         收敛（R191 名实双出口声明：未使能期修调**斜坡归零而非保持**）。
 *                         ⑤ 组态闸：fKc<0 或 >1、fTrimMaxMm<=0、fRampMmS<=0 → 锁存
 *                         bError，输出强制归零，解除沿 = bReset 上升沿。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_GantrySkewMonitor` 分工：闭环修调（本件）≠ 偏差监视
 *                         （那件）；与 `FB_DL_LoadShareDroop` 分工：轮廓误差耦合 ≠ 负载
 *                         调差。
 * 来源标签 (Source Tag) : T1-6 ◐（PLCopen MC 语义只借轮廓误差定义口径，交叉耦合法则为
 *                         公开控制理论定义 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 LREAL 修调组 + BOOL 组；
 *                         数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 向量模防零 + 周期缺省闸 + 非有限冻结 + 限幅 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（无状态机） ｜ R7 ✓ 一 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.1  R50 返修 R4：fDirX/fDirY 非有限
 *                         判据补 Inf 判（差自减 (x−x) <> 0），与 fErrX/fErrY
 *                         两侧口径一致（R79 双判对齐）；行为变更：方向向量
 *                         ±Inf 现判非有限冻结（原放行），验收向量同步补组。
 *                         2026-11-20  v1.0.0  R48 首版（批次 4 · 序号 16）
 *                         验收向量：X 误差主导 + 方向沿 X → fTrimY 修调、fTrimX 近零；
 *                         方向模 0 → bNoDir 零修调；退出使能斜坡归零无突跳。
 *==============================================================================*)

FUNCTION_BLOCK FB_DL_ContourCrossCouple
VAR_INPUT
    fErrX     : LREAL := 0.0;    // X 轴跟随误差 [mm] / X-axis following error [mm]
    fErrY     : LREAL := 0.0;    // Y 轴跟随误差 [mm] / Y-axis following error [mm]
    fDirX     : LREAL := 1.0;    // 轨迹方向向量 X 分量（与 Y 分量构成模 1 向量） [无量纲] / Path direction X component
    fDirY     : LREAL := 0.0;    // 轨迹方向向量 Y 分量 [无量纲] / Path direction Y component
    fKc       : LREAL := 0.5;    // 交叉耦合增益，域 [0,1] [无量纲] / Cross-coupling gain
    fTrimMaxMm: LREAL := 0.5;    // 修调限幅（对称 ±），域 > 0 [mm] / Trim limit [mm]
    fRampMmS  : LREAL := 10.0;   // 修调变化率限，域 > 0 [mm/s] / Trim rate limit [mm/s]
    fCycle    : LREAL := 0.0;    // 扫描周期（<=0 用缺省） [s] / Scan cycle, default used when <= 0
    bEnable   : BOOL := FALSE;   // 使能（FALSE=修调斜坡归零） [-] / Enable, FALSE ramps trim to zero
    bReset    : BOOL := FALSE;   // 复位，上升沿清组态故障锁存 [-] / Reset, rising edge clears config latch
END_VAR
VAR_OUTPUT
    fTrimX  : LREAL;             // X 轴修调注入（已限幅/斜坡） [mm] / X-axis trim injection [mm]
    fTrimY  : LREAL;             // Y 轴修调注入 [mm] / Y-axis trim injection [mm]
    bNoDir  : BOOL;              // 方向向量退化（模过小，零修调直通） [-] / Degenerate direction flag
    bError  : BOOL;              // 组态故障标志（锁存） [-] / Configuration fault flag, latched
END_VAR
VAR
    _fTrimX   : LREAL := 0.0;    // X 修调锁存镜像（斜坡收敛源） / X trim latch mirror
    _fTrimY   : LREAL := 0.0;    // Y 修调锁存镜像 / Y trim latch mirror
    _fTarX    : LREAL;           // 当拍 X 修调目标（斜坡前） [mm] / X trim target before ramp
    _fTarY    : LREAL;           // 当拍 Y 修调目标 [mm] / Y trim target before ramp
    _fEc      : LREAL;           // 当拍轮廓误差 [mm] / Contour error this scan
    _fDen     : LREAL;           // 方向向量模 [无量纲] / Direction vector magnitude
    _fCy      : LREAL;           // 当拍有效周期 [s] / Effective cycle this scan
    _fStep    : LREAL;           // 当拍最大斜坡步长 [mm] / Max ramp step this scan
    _bErrLatch: BOOL;            // 组态故障锁存位（解除沿 = bReset 上升沿） / Latched config fault
    rtReset   : R_TRIG;          // 复位沿实例，段 0 无条件调用 / Reset edge instance
    _bNonFin  : BOOL;            // 输入非有限当拍量 [-] / Non-finite input this scan
    _bNoDir   : BOOL;            // 方向退化当拍量（统一出口映射） / Degenerate direction internal
END_VAR
VAR CONSTANT
    DL_CCC_DIRMIN : LREAL := 1.0E-6;  // 方向向量模下限（防零） [无量纲] / Direction magnitude floor
    DL_CCC_EPS    : LREAL := 0.0;     // 非有限差值判零基准 [-] / Non-finite difference zero base
    DL_CCC_ONE    : LREAL := 1.0;     // 单位常量（增益域上界） [无量纲] / Unit constant
    DL_CCC_CYDEF  : LREAL := 0.01;    // 缺省扫描周期 [s] / Default scan cycle
    DL_CCC_TWO    : LREAL := 2.0;     // 平方指数 [-] / Square exponent base
END_VAR

(* —— 段 0：非有限判 + 组态闸 + 周期派生 + 沿刷新 —— *)
_bNonFin := (fErrX <> fErrX) OR ((fErrX - fErrX) <> DL_CCC_EPS)
         OR (fErrY <> fErrY) OR ((fErrY - fErrY) <> DL_CCC_EPS)
         OR (fDirX <> fDirX) OR ((fDirX - fDirX) <> DL_CCC_EPS)   // 方向 X 非有限（NaN 自反 + Inf 差自减，R79 双判口径对齐，v1.0.1） / Non-finite dir X, dual test
         OR (fDirY <> fDirY) OR ((fDirY - fDirY) <> DL_CCC_EPS);  // 方向 Y 非有限（同双判口径） / Non-finite dir Y, dual test
IF (fKc < 0.0) OR (fKc > DL_CCC_ONE) OR (fTrimMaxMm <= 0.0) OR (fRampMmS <= 0.0) THEN
    _bErrLatch := TRUE;                                     // 组态域闸：锁存（R188 解除沿 = bReset 上升沿） / Config gate: latch
END_IF
IF fCycle > 0.0 THEN
    _fCy := fCycle;                                         // 组态周期有效 / Configured cycle valid
ELSE
    _fCy := DL_CCC_CYDEF;                                   // 周期缺省兜底 / Default cycle fallback
END_IF
_fStep := fRampMmS * _fCy;                                  // 最大斜坡步长 [mm] / Max ramp step
rtReset(CLK := bReset);                                     // 复位沿，每拍必调 / Reset edge, every scan

(* —— 段 1：复位沿 —— *)
IF rtReset.Q THEN
    _bErrLatch := FALSE;                                    // 清组态故障锁存 / Clear config latch
END_IF

(* —— 段 2：轮廓误差与修调目标（故障/退化/非有限分支先行） —— *)
IF _bErrLatch THEN
    _fTarX := 0.0;                                          // 故障安全侧目标零 / Fault safe target zero
    _fTarY := 0.0;                                          // 故障安全侧目标零 / Fault safe target zero
    _bNoDir := FALSE;                                       // 故障期退化标志复位 / Degenerate flag reset
ELSIF _bNonFin THEN
    _fTarX := _fTrimX;                                      // 非有限冻结：目标 = 当前值（保持逼近） / Freeze target to current
    _fTarY := _fTrimY;                                      // 冻结 Y 目标 / Freeze Y target
    _bNoDir := FALSE;                                       // 非有限期不判退化 / No direction judgment
ELSE
    _fDen := SQRT(fDirX * fDirX + fDirY * fDirY);           // 方向向量模（判模后再用，无除零） / Direction magnitude
    IF _fDen < DL_CCC_DIRMIN THEN
        _fTarX := 0.0;                                      // 方向退化：零修调直通（R28 防零） / Degenerate: zero trim
        _fTarY := 0.0;                                      // 零修调 / Zero trim
        _bNoDir := TRUE;                                    // 置退化标志 / Raise degenerate flag
    ELSE
        _fEc := (fErrX * fDirX + fErrY * fDirY) / _fDen;    // 轮廓误差投影（分母模已过闸） / Contour error projection
        _fTarY := fKc * _fEc * fDirX;                       // 垂直分量还给 Y 弱轴 / Vertical component to Y
        _fTarX := -fKc * _fEc * fDirY;                      // 垂直分量还给 X 弱轴（反号） / Vertical component to X, negated
        IF _fTarX > fTrimMaxMm THEN
            _fTarX := fTrimMaxMm;                           // 目标上钳 / Clamp target high
        ELSIF _fTarX < -fTrimMaxMm THEN
            _fTarX := -fTrimMaxMm;                          // 目标下钳 / Clamp target low
        END_IF
        IF _fTarY > fTrimMaxMm THEN
            _fTarY := fTrimMaxMm;                           // 目标上钳 / Clamp target high
        ELSIF _fTarY < -fTrimMaxMm THEN
            _fTarY := -fTrimMaxMm;                          // 目标下钳 / Clamp target low
        END_IF
        _bNoDir := FALSE;                                   // 方向有效 / Direction valid
    END_IF
    IF NOT bEnable THEN
        _fTarX := 0.0;                                      // 未使能目标零（斜坡归零语义，头注释④） / Disabled target zero
        _fTarY := 0.0;                                      // 未使能目标零 / Disabled target zero
    END_IF
END_IF

(* —— 段 3：斜坡逼近（限步长收敛，方向突变/退出使能均无突跳） —— *)
IF _fTarX > (_fTrimX + _fStep) THEN
    _fTrimX := _fTrimX + _fStep;                            // X 正向限步收敛 / X ramp up
ELSIF _fTarX < (_fTrimX - _fStep) THEN
    _fTrimX := _fTrimX - _fStep;                            // X 负向限步收敛 / X ramp down
ELSE
    _fTrimX := _fTarX;                                      // X 步内到达 / X settle
END_IF
IF _fTarY > (_fTrimY + _fStep) THEN
    _fTrimY := _fTrimY + _fStep;                            // Y 正向限步收敛 / Y ramp up
ELSIF _fTarY < (_fTrimY - _fStep) THEN
    _fTrimY := _fTrimY - _fStep;                            // Y 负向限步收敛 / Y ramp down
ELSE
    _fTrimY := _fTarY;                                      // Y 步内到达 / Y settle
END_IF

(* —— 段 4：出口单点映射（名实双出口同源，R191） —— *)
fTrimX := _fTrimX;                                          // X 修调出口 / X trim outlet
fTrimY := _fTrimY;                                          // Y 修调出口 / Y trim outlet
bNoDir := _bNoDir AND (NOT _bErrLatch);                     // 退化标志出口（故障期复位） / Degenerate outlet
bError := _bErrLatch;                                       // 故障标志出口 / Error flag outlet

END_FUNCTION_BLOCK
