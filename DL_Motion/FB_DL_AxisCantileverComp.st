(*
  ==================================================================
  组件名 Component  : FB_DL_AxisCantileverComp
  分类   Category   : DL_Motion
  复杂度 Complexity  : cx4
  版本   Version    : 1.0.0
  功能   Purpose    : 悬臂轴重力下垂补偿。按位置 pos 在段点表（afSegX / afSegC，
                      基准负载下的补偿曲线）分段线性插值，再按实际负载与基准负载
                      之比缩放，得补偿量 fComp 叠加到位置指令；补偿上限钳制；
                      负载超上限判 ePayloadOver；曲表段点不严格递增判
                      eCurveDegenerate；上电首拍不输出补偿（自零起斜坡引入，
                      单拍步进上限 fStepMax）。
  来源   Source     : t1-6-plcopen（limits / comp 族）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；悬臂挠曲随负载 / 伸长
                      量的材料力学前馈修正为公开力学语义，clean-room 自研实现，
                      未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（ARRAY / LREAL 运算，无私有库、无幂运算符）
  作者   Author     : 道莅代码库 · PLC 编程专家（R56）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只算补偿量，不驱动轴、不改位置环（属主边界）；
                      二 故障优先级固定：eSensorBad > eCurveDegenerate > ePayloadOver
                         （R146 方向性：传感器失效冻结，曲表失效不输出，负载超限降级钳制）；
                      三 首拍斜坡：出口自零起按 fStepMax 单拍步进逼近目标（首拍不跳变）；
                      四 故障锁存（曲表退化 / 负载超限）解除路径 = bReset 上升沿（R188）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      fComp 为斜坡后的补偿量出口 [位置单位]；
                      eFault 为锁存回放；ePhaseBad 为非法相位兜底专用成员（R128）。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R56 首版（批 3 · 序号 13）
  ==================================================================
*)

TYPE E_DL_AcfPhase :
(
    eIdle  := 0,  // 未使能：出口保持 / disabled, the outlet holds
    eRun   := 10, // 运行：逐拍插值与斜坡 / running, interpolation and the ramp every scan
    eFault := 90  // 故障：成因锁存，出口冻结 / fault, the cause is latched, the outlet freezes
);
END_TYPE

TYPE E_DL_AcfFault :
(
    eNone             := 0, // 无成因 / no cause
    eCurveDegenerate  := 1, // 曲表退化：段点不严格递增或段数不足（故障级，与 bError 配对）/ a degenerate curve, fault grade paired with bError
    ePayloadOver      := 2, // 负载超上限（信息级，补偿按上限钳制）/ the payload is over the ceiling, the compensation clamps
    eSensorBad        := 3, // 位置或负载非有限（故障级，与 bError 配对）/ the position or the load is non finite, fault grade paired with bError
    ePhaseBad         := 4  // 非法相位兜底（故障级，与 bError 配对）/ illegal phase fallback, fault grade paired with bError
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisCantileverComp
VAR_INPUT
    bEnable  : BOOL := TRUE;    // 使能，失能时出口冻结保持 [-] / enable, the outlet holds when disabled
    bReset   : BOOL := FALSE;   // 复位上升沿清故障锁存并出口归零 [-] / reset rising edge clears the latch and zeroes the outlet
    fPos     : LREAL := 0.0;    // 轴实际位置 [位置单位] / the actual axis position [position unit]
    fLoadKg  : LREAL := 0.0;    // 负载质量 [千克] / the payload mass [kilogram]
    fLoadRef : LREAL := 10.0;   // 曲表基准负载 [千克]，域 大于零 / the curve reference load [kilogram], domain above zero
    fLoadMax : LREAL := 50.0;   // 负载上限 [千克]，域 大于零 / the payload ceiling [kilogram], domain above zero
    fCompMax : LREAL := 1.0;    // 补偿量上限 [位置单位]，域 大于零 / the compensation ceiling [position unit], domain above zero
    fStepMax : LREAL := 0.01;   // 首拍斜坡单拍步进上限 [位置单位每拍]，0 = 直通 / the ramp step ceiling per scan, zero is a passthrough
    afSegX   : ARRAY[1..16] OF LREAL := [0.0, 100.0, 200.0, 300.0, 400.0, 500.0, 600.0, 700.0, 800.0, 900.0, 1000.0, 0.0, 0.0, 0.0, 0.0, 0.0]; // 段点位置表（升序有效段）[位置单位] / the segment position table in ascending order [position unit]
    afSegC   : ARRAY[1..16] OF LREAL := [16(0.0)]; // 段点补偿量表（基准负载下）[位置单位] / the segment compensation table at the reference load [position unit]
    nSeg     : INT := 11;       // 有效段点数 [个]，域 2..16 / the valid segment count, domain two to sixteen
END_VAR
VAR_OUTPUT
    fComp    : LREAL := 0.0;  // 补偿量出口（叠加到位置指令）[位置单位] / the compensation outlet for the position command [position unit]
    ePhase   : E_DL_AcfPhase := E_DL_AcfPhase.eIdle; // 相位出口 [枚举] / phase outlet [enum]
    eFault   : E_DL_AcfFault := E_DL_AcfFault.eNone; // 成因出口，锁存回放 [枚举] / cause outlet replayed from the latch [enum]
    bError   : BOOL := FALSE; // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtReset  : R_TRIG; // 复位沿检测，段 0 无条件刷新 / reset edge, refreshed unconditionally in segment zero
    _ePhase  : E_DL_AcfPhase := E_DL_AcfPhase.eIdle; // 内部相位，CASE 唯一写入目标 / internal phase, the only CASE write target
    _eFaulC  : E_DL_AcfFault := E_DL_AcfFault.eNone; // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault  : BOOL := FALSE; // 故障锁存位 [-] / fault latch bit
    _bInit   : BOOL := FALSE; // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bInOk   : BOOL := FALSE; // 位置与负载均有限 [-] / both position and load are finite
    _bCfgOk  : BOOL := FALSE; // 组态参数域内 [-] / the configuration is inside the domain
    _bCurveOk: BOOL := FALSE; // 曲表结构合法 [-] / the curve structure is legal
    _bPayload: BOOL := FALSE; // 负载超上限标志 [-] / the payload over ceiling flag
    _nSegUse : INT := 11;     // 钳定后的段点数 [个] / the clamped segment count
    _nI      : INT := 1;      // 插值段游标 [段] / the interpolation segment cursor
    _nGuard  : INT := 0;      // 扫描守护计数 [次] / the scan guard [count]
    _fScale  : LREAL := 1.0;  // 负载缩放比 [无量纲] / the load scale ratio
    _fLoadUse: LREAL := 0.0;  // 钳定后的负载 [千克] / the clamped load [kilogram]
    _fTarget : LREAL := 0.0;  // 本拍补偿目标值 [位置单位] / the compensation target this scan [position unit]
    _fStep   : LREAL := 0.0;  // 本拍步进量 [位置单位] / the step this scan [position unit]
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支）/ segment 0, unconditional refresh of the edge detector
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge

// 段 1｜首扫初始化（R310）：出口自零起步（首拍不输出补偿）/ segment 1, first scan initialisation, the outlet starts at zero
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _ePhase := E_DL_AcfPhase.eRun; // 相位从运行起步 / the phase starts in run
    _eFaulC := E_DL_AcfFault.eNone; // 故障级成因清零 / clear the fault cause
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    fComp := 0.0; // 出口自零起步（首拍斜坡引入）/ the outlet starts at zero for the ramp in
END_IF

// 段 2｜复位沿作用域：清锁存 / 迁相位 / 出口归零（三项逐项声明）/ segment 2, reset edge scope declared item by item
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaulC := E_DL_AcfFault.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _ePhase := E_DL_AcfPhase.eRun; // 作用域二：迁回运行相 / scope two, migrate back to run
    fComp := 0.0; // 作用域三：出口归零（斜坡自零重引入）/ scope three, the outlet zeroes for a fresh ramp
END_IF

// 段 3｜组态域闸与曲表结构校验（R151 全覆盖）/ segment 3, the configuration gate and the curve structure check
_bInOk := (fPos = fPos) AND ((fPos - fPos) = (fPos - fPos)) AND (fLoadKg = fLoadKg) AND ((fLoadKg - fLoadKg) = (fLoadKg - fLoadKg)); // 位置与负载有限性 / finiteness of the position and the load
_bCfgOk := (fLoadRef > 0.0) AND (fLoadRef = fLoadRef) AND (fLoadMax > 0.0) AND (fLoadMax = fLoadMax) AND (fCompMax > 0.0) AND (fCompMax = fCompMax) AND (fStepMax >= 0.0) AND (fStepMax = fStepMax); // 组态参数域判定 / the configuration domain verdict
_nSegUse := nSeg; // 段点数直通 / the segment count passes through
IF _nSegUse < 2 THEN // 下越域 / below the floor
    _nSegUse := 2; // 回钳到二 / clamp to two
ELSIF _nSegUse > 16 THEN // 上越域 / above the ceiling
    _nSegUse := 16; // 回钳到十六 / clamp to sixteen
END_IF
_bCurveOk := _bCfgOk AND (_nSegUse >= 2); // 曲表结构初判 / the first curve verdict
_nI := 1; // 扫描游标起步 / start the scan cursor
_nGuard := 0; // 守护清零 / clear the guard
WHILE (_nI < _nSegUse) AND (_nGuard < 16) DO // 严格递增校验，守护为容量 / the strict monotonic check with the capacity as the guard
    _nGuard := _nGuard + 1; // 守护递增 / increment the guard
    IF afSegX[_nI] >= afSegX[_nI + 1] THEN // 段点非严格递增 / the points are not strictly increasing
        _bCurveOk := FALSE; // 判曲表退化 / the curve is degenerate
    END_IF
    _nI := _nI + 1; // 游标递增 / increment the cursor
END_WHILE

// 段 4｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 4, the phase machine with an ELSE fallback
CASE _ePhase OF
E_DL_AcfPhase.eIdle: // 未使能相：出口冻结保持 / the disabled phase, the outlet holds
    IF bEnable AND (NOT _bFault) THEN // 使能且无故障 / enabled and unfaulted
        _ePhase := E_DL_AcfPhase.eRun; // 迁运行相 / migrate to run
    END_IF

E_DL_AcfPhase.eRun: // 运行相：插值 + 缩放 + 钳制 + 斜坡 / the run phase, interpolate, scale, clamp and ramp
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_AcfPhase.eIdle; // 迁未使能相 / migrate to idle
    ELSIF (NOT _bInOk) OR (NOT _bCurveOk) THEN // 传感器失效或曲表退化（高优先级拦截）/ a sensor failure or a degenerate curve, the top priority interception
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        IF NOT _bInOk THEN // 传感器失效优先归因（R190 独立成因）/ the sensor failure takes the cause priority
            _eFaulC := E_DL_AcfFault.eSensorBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        ELSE // 曲表退化归因 / the degenerate curve cause
            _eFaulC := E_DL_AcfFault.eCurveDegenerate; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        END_IF
        _ePhase := E_DL_AcfPhase.eFault; // 迁故障相 / migrate to the fault phase
    ELSE // 正常计算 / the normal computation
        _fLoadUse := fLoadKg; // 负载直通 / the load passes through
        _bPayload := FALSE; // 负载超限标志预置假 / preset the payload flag to false
        IF _fLoadUse < 0.0 THEN // 负载负值回钳零 / a negative load clamps to zero
            _fLoadUse := 0.0; // 钳到零 / clamp to zero
        ELSIF _fLoadUse > fLoadMax THEN // 负载超上限 / the load is over the ceiling
            _fLoadUse := fLoadMax; // 钳到上限（信息级降级，R146 安全侧）/ clamp to the ceiling, the safe side
            _bPayload := TRUE; // 置负载超限标志 / raise the payload flag
        END_IF
        _fScale := _fLoadUse / fLoadRef; // 负载缩放比，除子为基准负载已证大于零 / the load scale with the proven reference divisor
        _fTarget := 0.0; // 目标值预置零 / preset the target to zero
        IF fPos <= afSegX[1] THEN // 左端外推钳位 / below the first point
            _fTarget := afSegC[1] * _fScale; // 取首段点补偿 / take the first point compensation
        ELSIF fPos >= afSegX[_nSegUse] THEN // 右端外推钳位 / above the last point
            _fTarget := afSegC[_nSegUse] * _fScale; // 取末段点补偿 / take the last point compensation
        ELSE // 域内分段线性插值 / the in domain piecewise interpolation
            _nI := 1; // 段游标起步 / start the segment cursor
            _nGuard := 0; // 守护清零 / clear the guard
            WHILE (_nI < _nSegUse) AND (_nGuard < 16) AND (fPos > afSegX[_nI + 1]) DO // 定位所在段 / locate the segment
                _nGuard := _nGuard + 1; // 守护递增 / increment the guard
                _nI := _nI + 1; // 游标递增 / increment the cursor
            END_WHILE
            _fTarget := afSegC[_nI] + (afSegC[_nI + 1] - afSegC[_nI]) * (fPos - afSegX[_nI]) / (afSegX[_nI + 1] - afSegX[_nI]); // 线性插值，除子为段宽已证大于零（严格递增校验）/ the linear interpolation with the proven segment width
            _fTarget := _fTarget * _fScale; // 负载缩放 / scale by the load
        END_IF
        IF _fTarget > fCompMax THEN // 补偿上限钳制 / clamp the compensation high
            _fTarget := fCompMax; // 钳到上限 / clamp to the ceiling
        ELSIF _fTarget < -fCompMax THEN // 补偿下限钳制 / clamp the compensation low
            _fTarget := -fCompMax; // 钳到下限 / clamp to the floor
        END_IF
        IF fStepMax <= 0.0 THEN // 步进上限为零 = 直通 / a zero step means a passthrough
            fComp := _fTarget; // 直通出口 / the passthrough outlet
        ELSE // 斜坡逼近 / the ramp approach
            _fStep := _fTarget - fComp; // 本拍剩余差 / the remaining difference
            IF _fStep > fStepMax THEN // 上行限步 / limit the upward step
                _fStep := fStepMax; // 钳到步进上限 / clamp to the step ceiling
            ELSIF _fStep < -fStepMax THEN // 下行限步 / limit the downward step
                _fStep := -fStepMax; // 钳到步进下限 / clamp to the step floor
            END_IF
            fComp := fComp + _fStep; // 斜坡推进 / advance the ramp
        END_IF
        IF _bPayload THEN // 负载超限信息级（不置故障锁存，R146 降级方向）/ the payload flag is informational, a degrade direction
            _eFaulC := E_DL_AcfFault.ePayloadOver; // 信息级成因 / the informational cause
        ELSE // 恢复后撤销 / revoked on recovery
            _eFaulC := E_DL_AcfFault.eNone; // 成因清零 / clear the cause
        END_IF
    END_IF

E_DL_AcfPhase.eFault: // 故障相：出口冻结保持，等复位沿 / the fault phase, the outlet freezes until the reset edge
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_AcfPhase.eIdle; // 迁未使能相 / migrate to idle
    END_IF

ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_AcfFault.ePhaseBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
    _ePhase := E_DL_AcfPhase.eFault; // 迁故障相 / migrate to the fault phase
END_CASE

// 段 5｜统一出口 / segment 5, the unified outlet
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eFault := _eFaulC; // 故障级成因锁存回放（R152）/ the fault cause replayed from the latch
ELSE
    eFault := _eFaulC; // 信息级成因直映 / the informational cause is mapped directly
END_IF
ePhase := _ePhase; // 相位出口单点映射 / single point phase outlet mapping
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
