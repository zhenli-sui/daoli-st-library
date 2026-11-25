(*
  FC_DL_SatSumArrayDint —— DINT 定长数组累加饱和，逐项防溢出
  分类：DL_MathData | 复杂度：2 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：对定长 8 元 DINT 数组的前 nCnt 项求和，每加一项前做「双侧直比」溢出判定，
        一旦越界即钳到 DINT 上下界、置 xSat 并停止累加（饱和语义，不做回绕）。
  契约：arrIn 输入数组（显式定长，R15）、nCnt 参与项数（0..8，越界自动截断）；diOut 饱和和；
        nUsed 实际参与项数；xSat 报告饱和。DINT 上下界在本文件内定义。
  边界：① 项数越域截断到 0..8；② 逐项溢出前置判定（禁 ABS 单侧比较）；③ 饱和即终止，结果单调可信；
        ④ 零全局、零物理地址、零库件依赖。
*)
FUNCTION FC_DL_SatSumArrayDint : DINT
VAR_INPUT
    arrIn : ARRAY[0..7] OF DINT;      // 输入数组（显式定长 8 元） [—] / The fixed length input array
    nCnt  : INT := 8;                 // 参与累加的项数（0..8） [个] / The number of items to sum
END_VAR
VAR_OUTPUT
    nUsed : INT;                      // 实际参与累加的项数 [个] / The number of items actually summed
    xSat  : BOOL;                     // 饱和发生标志（信息级） [—] / The saturation flag, informational
END_VAR
VAR
    i     : INT;                      // 遍历索引 [下标] / The traversal index
    diAcc : DINT;                     // 累加器 [—] / The accumulator
    diItem : DINT;                    // 当前项 [—] / The current item
    xStop : BOOL;                     // 饱和终止标志 [—] / The saturation stop flag
END_VAR
VAR CONSTANT
    DL_DINT_MAX : DINT := 2147483647; // DINT 上界（本件私有） [-] / The DINT maximum, private to this file
    DL_DINT_MIN : DINT := -2147483647 - 1; // DINT 下界（本件私有） [-] / The DINT minimum, private to this file
    DL_SA_NMAX  : INT := 8;           // 数组容量 [个] / The array capacity
    DL_SA_Z     : INT := 0;           // 整型零常量 [个] / The integer zero constant
END_VAR

FC_DL_SatSumArrayDint := 0;                           // 返回值预置零 / preset the return zero
xSat := FALSE;                                        // 饱和标志预置假 / preset the saturation flag false
nUsed := DL_SA_Z;                                     // 参与项数预置零 [个] / preset the used count zero
diAcc := 0;                                           // 累加器清零 [—] / clear the accumulator
xStop := FALSE;                                       // 终止标志预置假 / preset the stop flag false
IF nCnt < DL_SA_Z THEN                                // 项数下越界 / the count below the domain
    nCnt := DL_SA_Z;                                  // 截断到零 [个] / truncate to zero
END_IF
IF nCnt > DL_SA_NMAX THEN                             // 项数上越界 / the count above the capacity
    nCnt := DL_SA_NMAX;                               // 截断到容量 [个] / truncate to the capacity
END_IF
i := DL_SA_Z;                                         // 索引从零起 / start from the first item
WHILE (i < nCnt) AND NOT xStop DO                     // 显式递增逐项累加 / accumulate item by item
    diItem := arrIn[i];                               // 取当前项 [—] / take the current item
    IF (diItem > 0) AND (diAcc > (DL_DINT_MAX - diItem)) THEN // 正项上溢前置判定 / the positive overflow test
        diAcc := DL_DINT_MAX;                         // 钳到上界 / clamp to the maximum
        xSat := TRUE;                                 // 置饱和标志 / raise the saturation flag
        xStop := TRUE;                                // 终止后续累加 / stop the accumulation
    ELSIF (diItem < 0) AND (diAcc < (DL_DINT_MIN - diItem)) THEN // 负项下溢前置判定 / the negative overflow test
        diAcc := DL_DINT_MIN;                         // 钳到下界 / clamp to the minimum
        xSat := TRUE;                                 // 置饱和标志 / raise the saturation flag
        xStop := TRUE;                                // 终止后续累加 / stop the accumulation
    ELSE
        diAcc := diAcc + diItem;                      // 界内累加 / the safe accumulation
        nUsed := nUsed + 1;                           // 计入参与项数 [个] / count the summed item
    END_IF
    i := i + 1;                                       // 索引递增 [下标] / increment the index
END_WHILE
FC_DL_SatSumArrayDint := diAcc;                       // 饱和和出口 [—] / publish the saturated sum
END_FUNCTION
