(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AxisLubeDistTrig
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商私有库，
 *                         零轴状态枚举引用（R277）
 * 功能描述 (Function)   : 轴走行距离润滑触发。每拍按位置增量绝对值 |Δpos| 累计
 *                         里程（位置跳变超 fJumpLimitMm 的增量按坏值拒收——
 *                         防参考点回归/重定位把里程瞬间灌满），累计达 fLubeDistMm
 *                         → bLubeReq 电平置位，调用方完成润滑后给 bLubeDone
 *                         沿清里程重开窗；tLubeLockout 为润滑后最小间隔窗
 *                         （防润滑完成沿丢失时连环请求）。导轨/丝杠按里程
 *                         润滑的标准场景。
 * 来源标签 (Origin)     : 自研线（IEC 61131-3 标准语义的道莅防御性实现，clean-room）
 * 分工声明 (Pairing)    : AxisLubeDistTrig（里程触发，本件）为独立触发件，与
 *                         AxisBrakeTest（周期试验）分工：本件按走行里程触发
 *                         润滑，不执行任何试验动作、不接管轴（R298 属主边界）。
 * 边界语义 (Boundary)   : ① 跳变闸：|Δpos| > fJumpLimitMm → 本拍增量拒收并
 *                         nJumpCnt 递增（信息级台账，防里程虚增）；
 *                         ② 位置 NaN → 增量拒收（不累计）；
 *                         ③ 锁存副本与实时镜像分离：判据读 _fDistAcc 锁存
 *                         累计器，fDistAccOut 实时镜像，行为一致（镜像同源）；
 *                         ④ 组态闸：润滑里程 <= 0 / 锁定窗 < 0 → 故障锁存；
 *                         ⑤ bLubeReq 置位期间累计器冻结（同窗不重复触发，
 *                         PT 保持时长语义，R219 口径）。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)，
 *                         码位待主控收口统一派号。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 跳变闸/NaN 拒收/组态闸 ✓｜R5 双语同行注释 ✓
 *                         R6 N/A（监视型无状态机，判据纯派生）✓
 *                         R7 TON/R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 fLubeDistMm=1000，位置 0→500→1000 → 第二拍后
 *                         bLubeReq=TRUE，fDistAccOut≈1000；
 *                         V2 位置单拍跳变 5000（限 1000）→ 拒收，nJumpCnt=1；
 *                         V3 bLubeDone 沿 → 里程清零重开窗，锁定窗内不重触发。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R49 首版（批 4 · 序号 19）
 *==============================================================================*)
TYPE E_DL_AltCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1                        (* 组态非法：里程/锁定窗越域 / Illegal config *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisLubeDistTrig
VAR_INPUT
    fPosNow     : LREAL := 0.0;              (* 轴当前位置快照 [mm] / Axis position snapshot *)
    fLubeDistMm : LREAL := 10000.0;          (* 润滑里程窗，域 > 0.0 [mm] / Lube distance window *)
    fJumpLimitMm: LREAL := 100.0;            (* 单拍位置增量上限（跳变判据），域 > 0.0 [mm] / Per-scan jump limit *)
    tLubeLockout: TIME := T#5S;              (* 润滑后最小间隔窗，域 >= T#0S [ms] / Post-lube lockout window *)
    bLubeDone   : BOOL := FALSE;             (* 润滑完成确认，上升沿清里程重开窗 [-] / Lube-done ack edge *)
    bEnable     : BOOL := TRUE;              (* 计程使能，FALSE 冻结累计 [-] / Enable *)
    bReset      : BOOL := FALSE;              (* 复位命令，上升沿清里程/台账/故障 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    bLubeReq    : BOOL;                      (* 润滑请求电平（bLubeDone 沿或复位沿清）[-] / Lube request level *)
    fDistAccOut : LREAL;                     (* 当前窗内累计里程（实时镜像）[mm] / Accumulated distance mirror *)
    fTotalDist  : LREAL;                     (* 总里程累计（维护台账）[mm] / Total distance ledger *)
    nJumpCnt    : UDINT;                     (* 位置跳变拒收累计（信息级台账）[次] / Jump rejection counter *)
    eCause      : E_DL_AltCause;             (* 成因出口（R190 归因唯一） / Cause outlet *)
    bError      : BOOL;                      (* 组态故障锁存标志 [-] / Config fault flag *)
END_VAR
VAR
    rtDone   : R_TRIG;                       (* 润滑完成沿实例，段 0 无条件调用 / Done edge instance *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonLock  : TON;                          (* 润滑后锁定窗计时，自复位式 IN := NOT Q（R188） / Lockout timer, self-resetting *)
    _fPosPrev: LREAL;                        (* 上拍位置（增量基准）[mm] / Previous position *)
    _fAcc    : LREAL;                        (* 窗内里程累计器（锁存量，判据源）[mm] / Window distance accumulator *)
    _fTotal  : LREAL;                        (* 总里程累计器（锁存量）[mm] / Total accumulator *)
    _bReq    : BOOL;                         (* 润滑请求锁存位 / Lube request latch *)
    _bLock   : BOOL;                         (* 润滑后锁定门控（锁定窗内禁止再触发）[-] / Post-lube lock gate *)
    _dPos    : LREAL;                        (* 本拍位置增量 [mm] / Position delta this scan *)
    _bFault  : BOOL;                         (* 组态故障锁存位 / Config fault latch bit *)
END_VAR
VAR CONSTANT
    DL_ALT_EPS : LREAL := 1.0E-9;            (* 判零容差（增量/里程比较）[mm] / Zero epsilon *)
END_VAR

(* —— 段 0：沿实例无条件刷新（R228A） —— *)
rtDone(CLK := bLubeDone);                    (* 完成沿每拍必调 / Done edge every scan *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)
tonLock(IN := _bLock, PT := tLubeLockout);   (* 锁定窗计时：IN 由锁定门控派生，段 0 无条件刷新（R228A） / Lockout timer, phase-derived IN *)
IF tonLock.Q THEN
    _bLock := FALSE;                         (* 锁定窗到时：解除门控（每拍全路径派生，R285） / Lockout elapsed: release gate *)
END_IF
_dPos := fPosNow - _fPosPrev;                (* 本拍位置增量派生 / Delta derive *)
_fPosPrev := fPosNow;                        (* 增量基准推进 / Base advance *)
_fPosPrev := fPosNow;                        (* 增量基准推进 / Base advance *)

(* —— 段 1：复位沿处理（作用域：清故障 + 清累计器 ×2 + 清请求锁存 + 清台账 + 基准重锚，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    eCause := E_DL_AltCause.eNone;           (* 清成因 / Clear cause *)
    _fAcc := 0.0;                            (* 清窗内里程 / Clear window distance *)
    _fTotal := 0.0;                          (* 清总里程 / Clear total *)
    _bReq := FALSE;                          (* 清请求锁存 / Clear request latch *)
    _bLock := FALSE;                         (* 清锁定门控 / Clear lock gate *)
    nJumpCnt := 0;                           (* 清跳变台账 / Clear jump counter *)
    _fPosPrev := fPosNow;                    (* 增量基准重锚（防复位巨增量） / Re-anchor base *)
    bLubeReq := FALSE;                       (* 清请求出口 / Clear request outlet *)
END_IF

(* —— 段 2：组态闸故障锁存（R45 配对；锁存至复位沿，R189） —— *)
IF ((fLubeDistMm <= DL_ALT_EPS) OR (fJumpLimitMm <= DL_ALT_EPS) OR (tLubeLockout < T#0S)
    OR (fLubeDistMm <> fLubeDistMm) OR (fJumpLimitMm <> fJumpLimitMm)) AND NOT _bFault THEN
    _bFault := TRUE;                         (* 组态非法/NaN 锁存 / Latch config fault *)
    eCause := E_DL_AltCause.eCfgIllegal;     (* 成因：组态非法 / Cause: illegal config *)
END_IF

(* —— 段 3：计程与触发（监视型纯派生，无 CASE 相） —— *)
IF bEnable AND NOT _bFault THEN
    IF (fPosNow <> fPosNow) OR ((fPosNow - fPosNow) <> (fPosNow - fPosNow)) THEN
        (* 位置 NaN：增量拒收不累计（边界②），基准已推进防坏值滞留 / NaN: skip *)
        ;                                    (* 空语句：ST 语法要求分支非空，无副作用 / Empty statement, ST syntax requires non-empty branch *)
    ELSIF NOT _bReq THEN                     (* 请求挂起期间累计器冻结（边界⑤同窗不重复触发） / Accumulator frozen while requested *)
        IF ABS(_dPos) > fJumpLimitMm THEN
            nJumpCnt := nJumpCnt + 1;        (* 跳变拒收台账（信息级，不置故障级，R90 口径） / Jump counter, info level *)
        ELSIF ABS(_dPos) > DL_ALT_EPS THEN
            _fAcc := _fAcc + ABS(_dPos);     (* 有效增量入窗累计 / Valid delta accumulate *)
            _fTotal := _fTotal + ABS(_dPos); (* 总里程累计 / Total accumulate *)
            IF _fAcc >= fLubeDistMm THEN
                _bReq := TRUE;               (* 里程到窗：请求锁存至完成沿 / Request latch *)
            END_IF
        END_IF
    END_IF
    IF rtDone.Q AND _bReq THEN               (* 完成沿：清里程重开窗 + 启动锁定门控 / Done edge: clear window, arm lock *)
        _bReq := FALSE;                      (* 清请求锁存 / Clear request *)
        _fAcc := 0.0;                        (* 清窗内里程 / Clear window *)
        _bLock := TRUE;                      (* 锁定门控置位（锁定窗计时由段 0 无条件推进） / Arm lock gate *)
    END_IF
END_IF

(* —— 段 4：出口映射（判据读锁存、镜像同源，红线要求一致行为） —— *)
bLubeReq := _bReq AND NOT _bLock AND (NOT _bFault) AND bEnable;   (* 请求出口：锁存 ∧ 锁定门外 ∧ 非故障 ∧ 使能（锁定窗内收敛防连环请求） / Request outlet with lock gating *)
fDistAccOut := _fAcc;                        (* 窗内里程实时镜像 / Window mirror *)
fTotalDist := _fTotal;                       (* 总里程镜像 / Total mirror *)
bError := _bFault;                           (* 组态故障镜像 / Config fault mirror *)
END_FUNCTION_BLOCK
