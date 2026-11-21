(*
  ==================================================================
  组件名 Component  : FB_DL_RolloverCounterUdint
  分类   Category   : DL_Base
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : UDINT 域回绕计数器。计数沿推进，计数达回绕上限 uUpper 后
                      下一沿回到 0 并出回绕单拍脉冲 bRoll，圈数 nTurns 累计并饱和；
                      装载电平优先于计数沿；上限非法（0）时退化冻结并锁存故障码。
  来源   Source     : t2-1-lgf-counter（LGF Counter 回绕计数族 UDINT 变体）
  溯源   Origin     : 回绕计数属公开计数语义，clean-room 自研实现，未复制 LGF
                      或任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（TON 未用；仅 R_TRIG / FOR 无关；无位运算），
                      CODESYS / TwinCAT / InoProShop / Machine Expert 通用
  分工声明 Split     : 与 FB_DL_RolloverCounter（INT 属主）与 FB_DL_ModuloCounter
                      （取模索引属主）三角互引——本件为 UDINT 域回绕计数，
                      只出计数/圈数/回绕脉冲，不做取模索引换算、不做工艺计件。
                      INT 属主仍管有符号双向回绕，本件不接管负向语义。
  作者   Author     : 道莅代码库 · PLC 编程专家（R60）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 回绕一律「比较 + 赋值」，禁用 MOD（负数取余三平台歧义）：
                         自增前判 uCount >= uUpper，命中则置 0 并计一圈；
                      二 整数进位点自证：uUpper=59 时计数序列 …58→59→0 圈数 +1；
                         uUpper=0 判非法冻结（不成环，禁静默计成 0 长循环）；
                      三 自增域自证：仅在 uCount < uUpper 时执行 +1，而
                         uUpper <= 16#FFFF_FFFF，故不存在 16#FFFF_FFFF + 1 回绕；
                      四 装载 bLoad 电平优先于复位沿与计数沿；装载值超上限钳位；
                      五 使能 bEnable = FALSE 时语义为「冻结保持」（计数/圈数/
                         回绕脉冲均保持，本拍不出脉冲）——本条为 R191 声明行；
                      六 故障解除路径：上限恢复合法（uUpper >= 1）且复位沿到达，
                         故障相迁回 eIdle 并清锁存（R152 可达性自证：uUpper 为
                         输入引脚，可恒达）。
  接口偏离声明       : 派单示意 nPreset（有符号命名），UDINT 域按 R265 命名-类型
                      一致性落为 uPreset，语义一字不减。
  错误码   Codes    :
    16#0001_0610【信息级】装载值或现存计数超上限已钳位（同一语义共码，R90 反证：
                         二者都只由「钳到 uUpper」观测，无独立可观测差异，不加第 4 码）
    16#0001_0611【信息级】圈数已饱和（达 DINT 计数上限，停止累计）
    16#0001_0612【故障级】回绕上限非法（0），计数退化冻结（锁存至复位沿）
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 uUpper=59，连打 60 沿 → 第 60 沿后 uCount=0、nTurns=1、bRoll 单拍
    V2 uUpper=0 → eFrozen、码 0612、bError 锁存，计数保持
    V3 bLoad 与 bCount 同拍 → 装载优先，计数等于钳位后的 uPreset
  修订记录 Revision  :
    2026-11-21  v1.0.0  R60 首版（批 1 · 序号 3）
  ==================================================================
*)

TYPE E_DL_RolloverPhaseUd :
(
    eIdle   := 0,  // 空闲：未使能，计数与圈数保持 / idle, disabled, the count and the turns held
    eCount  := 10, // 计数：按装载与计数沿推进并回绕 / counting, driven by the load and the count edges with wrap around
    eFrozen := 20  // 冻结：上限非法，计数保持并报警 / frozen, the bound is illegal, the count held with the alarm
);
END_TYPE

FUNCTION_BLOCK FB_DL_RolloverCounterUdint
VAR_INPUT
    bEnable    : BOOL;  // 使能，FALSE 时冻结保持（边界五）/ the enable, false freezes and holds
    bReset     : BOOL;  // 复位上升沿：计数与圈数清零 / the reset rising edge, clears the count and the turns
    bCount     : BOOL;  // 计数上升沿：计数推进或回绕 / the count rising edge, advance or wrap
    bLoad      : BOOL;  // 装载电平，优先级最高（边界四）/ the level true load, the highest priority
    uPreset    : UDINT; // 装载预置值 [计数值]，超上限时钳位 / the load preset, clamped to the bound
    uUpper     : UDINT; // 回绕上限（含）[计数值]，合法域 1..16#FFFF_FFFF / the wrap bound inclusive, legal from one to the unsigned maximum
END_VAR
VAR_OUTPUT
    uCount    : UDINT;                  // 当前计数值 [计数值]，域 0..uUpper / the current count, from zero to the bound
    bRoll     : BOOL;                   // 本拍回绕单拍脉冲 [-] / the wrap one shot pulse of this scan
    nTurns    : DINT;                   // 累计圈数（饱和）[圈] / the accumulated turns, saturated
    bAtUpper  : BOOL;                   // 当前值已达回绕上限（逐拍重算）[-] / the count reached the bound, recomputed every scan
    eState    : E_DL_RolloverPhaseUd;   // 主状态机当前态 [状态] / the current state of the main machine
    bError    : BOOL;                   // 故障锁存位 [-] / the latched fault bit
    eErr      : UDINT;                  // 错误码，0 = 正常 / the error code, zero is ok
END_VAR
VAR
    _bInit     : BOOL := FALSE;                  // 首拍初始化标志（R310）/ the first scan flag
    _eState    : E_DL_RolloverPhaseUd := E_DL_RolloverPhaseUd.eIdle; // 内部状态寄存器，段 3 唯一写点 / the internal state register, single writer
    _uCount    : UDINT := 0;                     // 计数内部副本，段 5 单点映射 / the internal count copy, mapped once in segment five
    _nTurns    : DINT := 0;                      // 圈数内部副本，段 5 单点映射 / the internal turns copy, mapped once in segment five
    _bRoll     : BOOL := FALSE;                  // 回绕单拍内部位，段 1 预清段 5 映射 / the internal wrap pulse bit, preset then mapped
    _bFault    : BOOL := FALSE;                  // 故障锁存副本（仅复位沿清除）/ the fault latch copy, cleared only on the reset edge
    _bTurnSat  : BOOL := FALSE;                  // 圈数饱和指示（逐拍重算）[-] / the turn saturation flag, recomputed every scan
    _bClamped  : BOOL := FALSE;                  // 钳位事件标记（逐拍重算）[-] / the clamp event flag, recomputed every scan
    rtCount    : R_TRIG;                         // 计数沿实例，段 0 无条件刷新 / the count edge instance, refreshed unconditionally
    rtReset    : R_TRIG;                         // 复位沿实例，段 0 无条件刷新 / the reset edge instance, refreshed unconditionally
END_VAR
VAR CONSTANT
    DL_RCU_TURNMAX : DINT := 1000000000; // 圈数饱和上界 [圈]，留足 INT 域余量防溢出 / the turn saturation bound with margin against overflow
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支，R7）；本件无 TON / segment 0, the unconditional edge refresh
rtCount(CLK := bCount); // 计数沿 / the count edge
rtReset(CLK := bReset); // 复位沿 / the reset edge

// 段 1｜首拍初始化与单拍标志预清（单拍标志入清单，保持型量不入，R32 FB32-1）/ segment 1, the first scan init and the one shot preset
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _uCount := 0; // 计数显式清零 / clear the count explicitly
    _nTurns := 0; // 圈数显式清零 / clear the turns explicitly
    _bFault := FALSE; // 故障锁存显式清零 / clear the fault latch explicitly
    _eState := E_DL_RolloverPhaseUd.eIdle; // 状态显式落空闲 / place the state to idle explicitly
END_IF
_bRoll := FALSE; // 回绕脉冲预清零（先清后置，段 3 只写 TRUE）/ preset the wrap pulse false, the segment three only raises it
_bTurnSat := FALSE; // 饱和指示预清零 / preset the saturation flag false
_bClamped := FALSE; // 钳位标记预清零 / preset the clamp flag false

// 段 2｜组态域闸与钳位（上限非法 → 故障锁存；装载值/现存计数超上限 → 钳位，边界二四）/ segment 2, the configuration gate and the clamps
IF uUpper < 1 THEN // 上限非法：不成环 / an illegal bound, no ring exists
    _bFault := TRUE; // 锁存故障（段 4 迁移相）/ latch the fault, the segment four migrates the phase
ELSE // 上限合法：施加钳位 / a legal bound, apply the clamps
    IF uPreset > uUpper THEN // 装载值超上限 / the load preset above the bound
        _bClamped := TRUE; // 记钳位事件 / register the clamp event
    END_IF
    IF _uCount > uUpper THEN // 上限在线改小致现存计数越界（边界二回钳）/ the bound reduced online puts the count above it
        _uCount := uUpper; // 现存计数回钳（回钳后不再复判越界，R241）/ clamp the count back, no re-test afterwards
        _bClamped := TRUE; // 记钳位事件 / register the clamp event
    END_IF
END_IF

// 段 3｜主状态机（ENUM + CASE，ELSE 拦非法态）/ segment 3, the main machine with the illegal state guard
CASE _eState OF
    E_DL_RolloverPhaseUd.eIdle: // 空闲相：未使能或已复位 / the idle phase, disabled or reset
        IF bReset AND rtReset.Q THEN // 复位沿（空闲相也清零，复位作用域：清累计量）/ the reset edge, the scope is the accumulated quantity
            _uCount := 0; // 计数清零 / clear the count
            _nTurns := 0; // 圈数清零 / clear the turns
        END_IF
        IF bEnable AND (_bFault = FALSE) AND (uUpper >= 1) THEN // 迁入条件：使能且无故障且上限合法（R274 全量闸位复检）/ the entry with the full gate recheck
            _eState := E_DL_RolloverPhaseUd.eCount; // 迁入计数相 / enter the counting phase
        END_IF
    E_DL_RolloverPhaseUd.eCount: // 计数相：装载优先，其次计数沿，再次复位沿 / the counting phase, load first, then the count edge, then the reset edge
        IF bLoad THEN // 装载电平优先（边界四）/ the load level wins
            IF uPreset > uUpper THEN // 装载值超上限 / the preset above the bound
                _uCount := uUpper; // 钳到上限 / clamp to the bound
            ELSE // 装载值域内 / the preset inside the domain
                _uCount := uPreset; // 直接装载 / take the preset
            END_IF
        ELSIF rtCount.Q THEN // 计数沿：自增前判回绕（边界一三）/ the count edge, test the wrap before the increment
            IF _uCount >= uUpper THEN // 已达上限，本沿回绕 / at the bound, wrap on this edge
                _uCount := 0; // 回绕置零 / wrap to zero
                _bRoll := TRUE; // 置回绕单拍 / raise the wrap pulse
                IF _nTurns < DL_RCU_TURNMAX THEN // 圈数未饱和 / the turns not saturated
                    _nTurns := _nTurns + 1; // 圈数推进 / advance the turns
                ELSE // 圈数饱和 / the turns saturated
                    _bTurnSat := TRUE; // 置饱和指示 / raise the saturation flag
                END_IF
            ELSE // 未达上限，正常自增（不存在位型回绕）/ below the bound, a plain increment with no bit pattern wrap
                _uCount := _uCount + 1; // 计数自增 / advance the count
            END_IF
        ELSIF bReset AND rtReset.Q THEN // 复位沿（复位作用域：清累计量 + 清回绕脉冲由段 1 预清承担）/ the reset edge
            _uCount := 0; // 计数清零 / clear the count
            _nTurns := 0; // 圈数清零 / clear the turns
        END_IF
        IF (NOT bEnable) AND (_bFault = FALSE) THEN // 失能回空闲（不借故障相过桥，R211）/ disable returns to idle without bridging the fault phase
            _eState := E_DL_RolloverPhaseUd.eIdle; // 迁回空闲 / back to idle
        END_IF
    E_DL_RolloverPhaseUd.eFrozen: // 冻结相：上限非法，计数保持 / the frozen phase, illegal bound, the count held
        IF rtReset.Q AND (uUpper >= 1) THEN // 解除式：复位沿且上限已恢复合法（R152 可达）/ the release, a reset edge with a legal bound restored
            _bFault := FALSE; // 清故障锁存 / clear the fault latch
            _uCount := 0; // 复位作用域：清累计量 / the reset scope, clear the accumulated quantity
            _nTurns := 0; // 复位作用域：清累计量 / the reset scope, clear the accumulated quantity
            _eState := E_DL_RolloverPhaseUd.eIdle; // 故障相迁出边（迁回空闲）/ the exit edge back to idle
        END_IF
    ELSE // 非法枚举值拦截 / the illegal enumeration guard
        _eState := E_DL_RolloverPhaseUd.eIdle; // 落回空闲 / force back to idle
        _bFault := TRUE; // 置故障锁存 / latch the fault
END_CASE

// 段 4｜故障锁存迁移闸（置于解除段之后，R258；锁存即迁冻结相）/ segment 4, the fault latch to phase gate, placed after the release
IF _bFault AND (_eState <> E_DL_RolloverPhaseUd.eFrozen) THEN // 已锁存但未在冻结相 / latched but not in the frozen phase
    _eState := E_DL_RolloverPhaseUd.eFrozen; // 迁入冻结相 / enter the frozen phase
END_IF

// 段 5｜统一出口（内部副本单点映射，R180；故障码锁存回放，R187）/ segment 5, the unified outlet
uCount := _uCount; // 计数出口 / the count outlet
nTurns := _nTurns; // 圈数出口 / the turns outlet
bRoll := _bRoll; // 回绕单拍出口 / the wrap pulse outlet
bAtUpper := (_uCount >= uUpper) AND (uUpper >= 1); // 达上限指示（上限非法时不宣称，逐拍重算）/ the at bound flag, recomputed every scan
eState := _eState; // 状态出口 / the state outlet
bError := _bFault; // 故障位出口（与锁存同源）/ the fault bit outlet from the same latch
IF _bFault THEN // 故障锁存回放优先 / the latched fault replays first
    eErr := 16#0001_0612; // 故障级：回绕上限非法，计数退化冻结 / fault grade, the illegal bound with the frozen count
ELSIF _bClamped THEN // 其次钳位信息级 / then the clamp informational code
    eErr := 16#0001_0610; // 信息级：超上限已钳位 / informational, clamped to the bound
ELSIF _bTurnSat THEN // 再次圈数饱和信息级 / then the saturation informational code
    eErr := 16#0001_0611; // 信息级：圈数已饱和 / informational, the turns saturated
ELSE // 无事件 / no event
    eErr := 16#0000_0000; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
