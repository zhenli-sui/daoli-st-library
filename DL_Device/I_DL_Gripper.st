(*
    I_DL_Gripper —— 平行夹爪契约
    ------------------------------------------------------------------
    分类      : DL_Device / Actuator
    前缀      : I_DL_
    版本      : 1.0.0
    溯源      : T2-6 Rockwell AOI（只借「设备级 AOI 粒度 = 阀 / 电机 / 夹爪三件套」
                这一分类事实）；T1-5 开源契约-实现分离范式（Apache-2.0 公开资料，
                仅借分层思想）；方法签名、属性集合、枚举引用 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3（第3版）接口语法，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R18）
    ------------------------------------------------------------------
    功能说明  : 把「夹爪」的对外能力收敛为 7 个只读属性加 4 个方法，实现类可换电动 /
                气动 / 伺服夹爪而工艺层零改动（面向接口编程，依赖注入）；
                方法均为一发即走的单发语义，结果经属性回读，方法内部不含跨扫描周期
                状态驻留（跨周期动作在实现块主体完成）；
                ClearFault 只清锁存，绝不隐式产生动作——热复位必须先排除物理原因；
                职责边界：本件只是契约，不采集信号、不驱动电磁阀，全部实现归
                FB_DL_ParallelGripper。
    错误码    : 本件为接口契约，无实现无码位；码位见 FB_DL_ParallelGripper
                （族内 5 槽 16#0003_0166 / 0167 / 032A / 032B / 032C 全部归实现件）
    码位总账  : 不占码位（接口件），实现件码位见 16#0003_0166 / 16#0003_0167 / 16#0003_032A / 16#0003_032B / 16#0003_032C
    状态机    : N/A —— 接口无实现体，状态机归实现件（E_DL_GripperState 随实现件发布）
    采样约定  : 接口不含时间量；实时性由实现件在其所在任务中承担
    修订记录  : 2026-11-16 v1.0.0 首次入库（R18）
*)

(*-----------------------------------------------------------------------------
 * 接口: I_DL_Gripper
 * 契约结构: 只读属性段（GET，7 个）+ 方法段（4 个）
 * 方法数约束: 4 个，满足接口方法不超过 6 个的拆分红线（职责未过载）
 * 边界防错: 故障锁存期间动作方法一律拒绝；ClearFault 只清锁存不产生动作；
 *           eHealth 引用库内唯一属主枚举 E_DL_Ne107Status，本件不重声明（R13 纪律）
 *----------------------------------------------------------------------------*)
INTERFACE I_DL_Gripper

// ---- 属性段（全部只读 GET）------------------------------------------------

PROPERTY bOpened           : BOOL              // 全开到位 / fully opened
PROPERTY bClosed           : BOOL              // 闭合到位（含夹持工件）/ fully closed, the workpiece clamped
PROPERTY bWorkpiecePresent : BOOL              // 工件在位（工件检测信号）/ workpiece present, from the part sensor
PROPERTY fWidth            : REAL              // 当前开口宽度 [mm] / current opening width [mm]
PROPERTY eHealth           : E_DL_Ne107Status  // 健康状态，引用库内唯一属主枚举 / health state, referencing the single owner enum
PROPERTY uErrorId          : UDINT             // 末次故障码，0 = 无故障，段位 16#0003_ / last error code, 0 = none, family 16#0003_
PROPERTY bError            : BOOL              // 故障锁存中，TRUE = 存在未复位故障 / fault latched, TRUE means an unrecovered fault exists

// ---- 方法段（单发指令，结果经属性回读）------------------------------------

METHOD Open : BOOL                             // 请求张开，到位由 bOpened 反映 / request opening, arrival is reflected by bOpened
VAR_INPUT
END_VAR

    END_METHOD

METHOD Close : BOOL                            // 请求闭合到指定夹持力 / request closing at the given clamping force
VAR_INPUT
    fForceSetpoint : REAL;                     // 目标夹持力 [%]，范围 0.0~100.0 / target clamping force [%], range 0.0~100.0
END_VAR

    END_METHOD

METHOD Release : BOOL                          // 松开并撤力，区别于 Open：不放到位只泄力 / release and drop the force, unlike Open it does not drive to the open end
VAR_INPUT
END_VAR

    END_METHOD

METHOD ClearFault : BOOL                       // 清故障锁存（热复位），不产生任何动作 / clear the fault latch, produces no motion
VAR_INPUT
END_VAR

    END_METHOD
END_INTERFACE
