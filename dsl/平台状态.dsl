FUNCTION_MODEL Link16_Platform_System_Status {

    // 1. 参与者定义
    // 定义了此功能模型中涉及的各种角色
    ACTORS {
        Own_Unit: C2_JU; // 添加 Own_Unit 作为 NOTIFY 的默认发送者
        C2_JU_A: C2_JU; // C2单元 "A"，通常作为发起者、控制者或请求者
        C2_JU_B: C2_JU; // C2单元 "B"，通常作为被请求者或另一个控制者
        Reporting_JU: GENERIC_PLATFORM; // 任何正在报告其自身状态的单元 (C2或Non-C2)
        Controlled_Unit: GENERIC_PLATFORM; // 一个被C2_JU_A控制的单元 (可能报告也可能不报告自身状态)
        Receiving_JU: GENERIC_PLATFORM; // 任何接收J13消息并需要处理数据冲突的单元
        Operator_A: GENERIC_PLATFORM; // C2_JU_A 的操作员
        Operator: NON_IU;         // 添加 Operator Actor 用于 NOTIFY
        System_Log: NON_IU;       // 添加 System_Log Actor 用于 NOTIFY
    }

    // 2. 消息定义
    // 定义了流程中使用的J系列消息
    MESSAGES {
        J13.X; // 平台和系统状态 (J13.0, J13.2, J13.3, J13.5, J13.6 等)
        J7.1;  // 数据更新请求
        J10.5; // 控制单元报告 (用于确定谁在控制谁)
    }

    // 3. 数据元素取值定义
    // 定义了消息字段中使用的特定离散值
    DISCRETES {
        // J7.1 Data Update Request Action 字段
        ENUM J7_1_Action FOR J7.1.DataUpdateRequestAction {
            DataUpdateRequestByTN = 1 "Data Update Request by TN";
        }

        // J13.X (J13.2C2/C7) Type of Stores 字段
        ENUM J13_Stores_Type FOR J13.X.Type_of_Stores {
            NoStatement = 0 "No Statement";
        }

        // J13.X (J13.2C2/C7) Number of Stores 字段
        ENUM J13_Stores_Number FOR J13.X.Number_of_Stores {
            NoStatement = 63 "No Statement";
        }
    }

    // 4. 全局状态声明
    // 定义了在多个流程实例间共享的状态变量
    STATES {
        // 存储 {Controlled_JU_TN -> Controller_C2_JU} 的映射, 基于J10.5更新
        Unit_Control_Map: DICTIONARY;
        // 存储 {Unit_TN -> {StatusData, Source_TN, Priority}} 的缓存
        Unit_Status_Cache: DICTIONARY;
        // 存储 {Controlled_JU_TN -> {Is_Proxy_Active, Timer_ID}}
        Proxy_Report_Status: DICTIONARY;
    }

    // 5. 数据映射 (未使用)
    MAPPINGS {
    }

    // =============================================
    //
    // 核心流程 (Core Procedure)
    //
    // =============================================

    PROCEDURE Core_Manage_Platform_System_Status "Manages all scenarios (reporting, requesting, monitoring, and receiving) for platform status." {
        TRIGGER "JU Enters Network"
                 OR "JU Status Significant Change"
                 OR "Periodic Status Report Timer Expired"
                 OR MESSAGE_RECEIVED J7.1 FROM C2_JU_A
                 OR "Status_Data_Required"
                 OR "Control_Assumed"
                 OR MESSAGE_RECEIVED J13.X FROM Reporting_JU;

        STEPS {

            // 分支 1: (场景一: 单元报告自身状态)
            IF "JU Enters Network"
                    OR "JU Status Significant Change"
                    OR "Periodic Status Report Timer Expired"
                    OR MESSAGE_RECEIVED J7.1(Reference_TN == Reporting_JU.TN) FROM C2_JU_A THEN {

                // 运行在 'Reporting_JU' 的上下文中

                // 1. 检查 J7.1 触发 (场景 1 - 仅限C2单元)
                IF "Trigger was RECEIVED J7.1" AND (Reporting_JU.Type != "C2_JU") THEN {
                    STEP "J7.1 request received, but unit is not C2. Ignoring trigger.";
                    TERMINATE;
                }

                // 2. 准备 J13 消息数据
                ASSIGN My_Status_Data = "Get_Own_Platform_Status()";

                // 3. 广播 J13 消息 (直接调用工具流程)
                STEP "Broadcasting own J13 status.";
                CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                    Sender = Reporting_JU,
                    MessageType = "J13.X",
                    Params = My_Status_Data,
                    Mode = "BROADCAST",
                    Recipient = NULL,
                    ToAddress = NULL
                );
            }

            // 分支 2: (场景二: C2单元主动请求另一个单元的状态)
            ELSE_IF "Status_Data_Required" THEN {
                // 运行在 'C2_JU_A' (请求方) 的上下文中

                // 逻辑: 触发事件 "Status_Data_Required" 自身应包含所需数据的信息
                ASSIGN Req_Type = "Get_Requirement_Type_From_Event()";
                ASSIGN Req_TN = "Get_Requirement_TN_From_Event()";

                // 场景 2A: 请求一个“受控单元”的状态
                IF Req_Type == "Controlled_Air_Track" THEN {
                    CALL Sub_Request_Controlled_Unit_Status(Requester = C2_JU_A, Target_Controlled_TN = Req_TN);
                }
                // 场景 2B: 请求另一个“C2单元”自身的状态
                ELSE_IF Req_Type == "C2_JU_Itself" THEN {
                    ASSIGN Target_C2_Actor = "Get_Actor_By_TN(Req_TN)";
                    CALL Sub_Request_C2_Unit_Status(Requester = C2_JU_A, Target_C2_JU = Target_C2_Actor);
                }
                ELSE {
                    STEP "Invalid requirement type.";
                    TERMINATE;
                }
            }

            // 分支 3: (场景三: C2单元代理报告其下属单元的状态)
            ELSE_IF "Control_Assumed" THEN {
                // 运行在 'C2_JU_A' (控制方) 的上下文中

                // 逻辑: 从事件获取被控制的单元
                ASSIGN Subject_JU = "Get_Controlled_Unit_From_Event()"; // 即 'Controlled_Unit'

                // 检查: 单元是否不自报告 或 处于静默?
                IF Subject_JU.Reports_Own_Status == FALSE OR "Subject_JU.Is_In_Radio_Silence == TRUE" THEN {
                    // 场景 3 (情况 A 和 C): 立即开始代理报告
                    STEP "Scenario 3A/C: Unit not self-reporting or in silence. Starting proxy reporting.";
                    CALL Sub_Manage_Proxy_Reporting(Controller = C2_JU_A, Subject_JU = Subject_JU, Reason = "INITIAL_CONTROL_OR_SILENCE");
                    TERMINATE;
                }
                ELSE {
                    // 场景 3 (情况 B 的监控): 单元正在自报告, C2必须启动看门狗监控
                    STEP "Scenario 3B/C: Unit is self-reporting. Starting monitoring watchdog.";
                    ASSIGN Watchdog_Timer_ID = "Generate_Timer_ID(Subject_JU.TN)";
                    ASSIGN Update_Period = "Get_Expected_J13_Update_Period()";

                    // 启动看门狗定时器 (超时周期为2个更新周期)
                    C2_JU_A START_TIMER Watchdog_Timer_ID FOR 30 SECONDS;

                    // 循环监控
                    WHILE C2_JU_A.Is_Controlling(Target=Subject_JU) == TRUE DO {
                        WAIT {
                            // 3a. 成功: 收到该单元的 J13，重置定时器
                            ON MESSAGE_RECEIVED J13.X FROM Subject_JU THEN {
                                STEP "Monitoring: Received J13 from controlled unit. Resetting watchdog timer.";
                                C2_JU_A RESET_TIMER Watchdog_Timer_ID;
                            }

                            // 3b. 失败: (情况 B 触发) 2个周期未收到 J13
                            ON TIMER_EXPIRED(Watchdog_Timer_ID) THEN {
                                STEP "Scenario 3B: J13 watchdog timer expired. Starting proxy reporting.";
                                CALL Sub_Manage_Proxy_Reporting(Controller = C2_JU_A, Subject_JU = Subject_JU, Reason = "J13_TIMEOUT");
                                TERMINATE; // 监控流程终止，代理流程接管
                            }

                            // 3c. 条件: (情况 C 触发) 单元中途进入无线电静默
                            ON "Controlled_Unit_Enters_Radio_Silence" THEN {
                                STEP "Scenario 3C: Unit entered radio silence mid-monitoring. Starting proxy reporting.";
                                C2_JU_A STOP_TIMER Watchdog_Timer_ID; // 停止看门狗
                                CALL Sub_Manage_Proxy_Reporting(Controller = C2_JU_A, Subject_JU = Subject_JU, Reason = "RADIO_SILENCE");
                                TERMINATE; // 监控流程终止，代理流程接管
                            }
                        }
                    }
                }
            }

            // 分支 4: (补充规则 1: J13 消息的被动接收与数据冲突处理)
            ELSE_IF MESSAGE_RECEIVED J13.X FROM Reporting_JU THEN {
                // 运行在 'Receiving_JU' 的上下文中
                ASSIGN Received_Msg_Data = "Extract_Message_Data()";
                CALL Sub_Process_Received_J13_Status(
                    Receiver = Receiving_JU,   // 'Receiving_JU' 是此分支的逻辑主体
                    Sender = Reporting_JU,
                    Received_Msg = Received_Msg_Data
                );
            }
        }
    }

    // =============================================
    //
    // 子流程 (Sub-procedures)
    //
    // =============================================

    // 子流程 (场景 2A): C2_A 请求 C2_B 所控制的单元的状态
    PROCEDURE Sub_Request_Controlled_Unit_Status(Requester: STRING, Target_Controlled_TN: INTEGER) "Handles Scenario 2A: Requesting status of a controlled air track from its controller." {
        STEPS {
            // 1. 查找控制单元
            ASSIGN Controller_TN = Unit_Control_Map.get(TN=Target_Controlled_TN);

            IF Controller_TN == NULL THEN {
                STEP "Log error: Cannot request status, controller for TN is unknown.";
                CALL Atomic_Alert_Operator(Recipient = Operator_A, Message = "Request failed: Controller for track is unknown.");
                TERMINATE;
            }

            // 2. 识别控制者 (C2_JU_B)
            ASSIGN C2_JU_B = "Get_Actor_By_TN(Controller_TN)";

            // 3. 发送 J7.1 请求 (直接调用工具流程)
            ASSIGN Msg_Params = {
                DataUpdateRequestAction = J7_1_Action.DataUpdateRequestByTN,
                Reference_TN = Target_Controlled_TN
            };
            CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                Sender = Requester,
                MessageType = "J7.1",
                Params = Msg_Params,
                Mode = "SEND",
                Recipient = C2_JU_B,
                ToAddress = NULL
            );

            // 4. 等待 C2_JU_B 的 J13 响应
            WAIT FOR 30 SECONDS {
                // 4a. 成功: 收到匹配的 J13 响应
                ON MESSAGE_RECEIVED J13.X(Reference_TN == Target_Controlled_TN) FROM C2_JU_B THEN {
                    STEP "Successfully received J13 status for controlled track.";
                    CONTINUE;
                }
                // 4b. 拒绝 (逻辑补充)
                ON "MESSAGE_RECEIVED CANTCO_Response_for_J7.1 from C2_JU_B" THEN {
                    STEP "Controller C2_JU_B explicitly refused the J7.1 request.";
                    CALL Atomic_Alert_Operator(Recipient = Operator_A, Message = "Request refused by controller C2_JU_B.");
                    TERMINATE;
                }
                // 4c. 超时 (逻辑补充)
                ON TIMEOUT THEN {
                    STEP "Timeout: Did not receive J13 response from controller C2_JU_B.";
                    CALL Atomic_Alert_Operator(Recipient = Operator_A, Message = "Request timed out, no J13 response from C2_JU_B.");
                    TERMINATE;
                }
            }
        }
    }

    // 子流程 (场景 2B): C2_A 请求 C2_B 自身的状态
    PROCEDURE Sub_Request_C2_Unit_Status(Requester: STRING, Target_C2_JU: STRING) "Handles Scenario 2B: Requesting status of another C2 JU itself." {
        STEPS {
            // 1. 发送 J7.1 请求 (直接调用工具流程)
            ASSIGN Msg_Params = {
                DataUpdateRequestAction=J7_1_Action.DataUpdateRequestByTN,
                Reference_TN=Target_C2_JU.TN
            };
            CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                Sender = Requester,
                MessageType = "J7.1",
                Params = Msg_Params,
                Mode = "SEND",
                Recipient = Target_C2_JU,
                ToAddress = NULL
            );

            // 2. 等待 C2_JU_B (即 Target_C2_JU) 的 J13 响应
            WAIT FOR 30 SECONDS {
                // 2a. 成功: 收到匹配的 J13 响应 (源TN==参考TN)
                ON MESSAGE_RECEIVED J13.X(Reference_TN == Target_C2_JU.TN) FROM Target_C2_JU THEN {
                    STEP "Successfully received J13 status for C2 JU.";
                    CONTINUE;
                }
                // 2b. 拒绝 (逻辑补充)
                ON "MESSAGE_RECEIVED CANTCO_Response_for_J7.1 fromTarget_C2_JU" THEN {
                    STEP "Target C2 JU explicitly refused the J7.1 request.";
                    CALL Atomic_Alert_Operator(Recipient = Operator_A, Message = "Request refused by target C2 JU.");
                    TERMINATE;
                }
                // 2c. 超时 (逻辑补充)
                ON TIMEOUT THEN {
                    STEP "Timeout: Did not receive J13 response from target C2 JU.";
                    CALL Atomic_Alert_Operator(Recipient = Operator_A, Message = "Request timed out, no J13 response from target C2 JU.");
                    TERMINATE;
                }
            }
        }
    }

    // 子流程 (场景 3 - A/B/C): 启动并维持对下属单元的代理报告
    PROCEDURE Sub_Manage_Proxy_Reporting(Controller: STRING, Subject_JU: STRING, Reason: STRING) "Handles Scenario 3 (Cases A, B, or C Action): C2 JU starts and maintains periodic proxy reporting." {
        STEPS {
            // 1. 记录代理状态
            CALL Proxy_Report_Status.set(TN=Subject_JU.TN, Data={Is_Proxy_Active= TRUE});
            STEP "Proxy reporting loop starting for unit.";

            // 2. 发送初始的 J13 代理报告 (直接调用工具流程)
            ASSIGN Initial_Status_Data = "Get_Local_Data_For_Unit(Subject_JU)";
            CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                Sender = Controller,
                MessageType = "J13.X",
                Params = Initial_Status_Data,
                Mode = "BROADCAST",
                Recipient = NULL,
                ToAddress = NULL
            );

            // 3. 维持周期性代理报告
            WHILE Proxy_Report_Status.get(TN=Subject_JU.TN).Is_Proxy_Active == TRUE DO {
                WAIT {
                    // 3a. 周期性定时器触发
                    ON "Periodic_Proxy_Timer_Expired" THEN {
                        ASSIGN Periodic_Status_Data = "Get_Local_Data_For_Unit(Subject_JU)";
                        // 广播周期性 J13 代理报告 (直接调用工具流程)
                        CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                            Sender = Controller,
                            MessageType = "J13.X",
                            Params = Periodic_Status_Data,
                            Mode = "BROADCAST",
                            Recipient = NULL,
                            ToAddress = NULL
                        );
                        STEP "Periodic proxy report sent. Resetting timer.";
                    }

                    // 3b. 停止条件: 受控单元恢复了自行报告
                    ON MESSAGE_RECEIVED J13.X FROM Subject_JU THEN {
                        STEP "Scenario 3 Stop: Controlled unit has resumed own reporting. Stopping proxy.";
                        CALL Sub_Stop_Proxy_Reporting(Controller = Controller, Subject_JU = Subject_JU);
                        // 代理报告任务终止
                        TERMINATE;
                    }

                    // 3c. (可选) 停止条件: C2单元不再控制该单元
                    ON "Control_Terminated" THEN {
                        STEP "Control terminated. Stopping proxy.";
                        CALL Sub_Stop_Proxy_Reporting(Controller = Controller, Subject_JU = Subject_JU);
                        TERMINATE;
                    }
                }
            }
        }
    }

    // 子流程 (场景 3 - 停止): 停止代理报告
    PROCEDURE Sub_Stop_Proxy_Reporting(Controller: STRING, Subject_JU: STRING) "Stops the proxy reporting for a specific unit." {
        STEPS {
            CALL Proxy_Report_Status.set(TN=Subject_JU.TN, Data={Is_Proxy_Active= false});
            STEP "C2 JU shall cease its reporting.";
        }
    }

    // 子流程 (规则 1): 处理收到的 J13 消息 (数据冲突解决)
    PROCEDURE Sub_Process_Received_J13_Status(Receiver: STRING, Sender: STRING, Received_Msg: DICTIONARY) "Handles Rule 1: Data conflict resolution for incoming J13 messages." {
        STEPS {
            ASSIGN Target_TN = Received_Msg.Reference_TN;
            ASSIGN New_Data = Received_Msg.Status_Data;

            // 1. 确定新报告的优先级 (逻辑已上移至此)
            ASSIGN New_Priority = 99; // 默认为最低优先级
            IF Sender.TN == Target_TN THEN {
                // 规则1: 平台自己的报告，优先级最高 (P1)
                ASSIGN New_Priority = 1;
            }
            ELSE_IF Unit_Control_Map.get(TN=Target_TN) == Sender.TN THEN {
                // 规则2: 控制该平台的C2 JU的报告，优先级次之 (P2)
                ASSIGN New_Priority = 2;
            }

            // 2. 获取缓存的旧数据
            ASSIGN Current_Entry = Unit_Status_Cache.get(TN=Target_TN);

            // 3. 比较优先级 (P1 = 1, P2 = 2. 优先级值越小，优先级越高)
            IF Current_Entry == NULL OR New_Priority <= Current_Entry.Priority THEN {
                // 4. 接受新数据: 新数据优先级更高，或没有旧数据
                STEP "Accepting new J13 data based on priority rules.";
                CALL Atomic_Update_Status_Cache(
                    Target_TN = Target_TN,
                    New_Data = New_Data,
                    Source_TN = Sender.TN,
                    Priority = New_Priority
                );
            }
            ELSE {
                // 5. 拒绝新数据: 缓存的数据优先级更高
                STEP "Discarding new J13 data; existing data has higher priority.";
                TERMINATE;
            }
        }
    }

    // 子流程 (规则 2): J13 语音信道内容规范
    // (这是一个描述性流程，定义了发送J13时的内容约束)
    PROCEDURE Rule_J13_Voice_Channel_Content() "Describes Rule 2: Content specification for J13 Voice Group A and B channels." {
        STEPS {
            STEP "When populating J13 Platform and System Status messages, the Voice Group A and B Channels fields SHALL be the channels on which the Reference TN (the unit being reported on) is operating.";
        }
    }

    // 子流程 (规则 3): J13 弹药数据解释
    // (这是一个描述性流程，定义了接收J13时的解释规则)
    PROCEDURE Rule_Interpret_J13_Stores(Type_of_Stores: INTEGER, Number_of_Stores: INTEGER) "Describes Rule 3: Interpretation logic for J13.2C2 and J13.2C7 stores data." {
        STEPS {
            // (1) 报告具体数量
            IF Type_of_Stores != J13_Stores_Type.NoStatement AND Number_of_Stores != J13_Stores_Number.NoStatement THEN {
                STEP "INTERPRETATION: Reports the aircraft's current specific onboard inventory (0 to 62 units) of that Type of Stores.";
            }
            // (2) 报告有此类型 (但不报数量)
            ELSE_IF Type_of_Stores != J13_Stores_Type.NoStatement AND Number_of_Stores == J13_Stores_Number.NoStatement THEN {
                STEP "INTERPRETATION: That Type of Stores is currently carried, but no data is reported about the number.";
            }
            // (3) 报告有此数量 (但不报类型)
            ELSE_IF Type_of_Stores == J13_Stores_Type.NoStatement AND Number_of_Stores != J13_Stores_Number.NoStatement THEN {
                STEP "INTERPRETATION: Reports the specific onboard inventory of an unspecified type of weapon.";
            }
            // (4) 未报告
            ELSE {
                STEP "INTERPRETATION: No data is reported.";
            }
        }
    }

    // =============================================
    //
    // 原子流程 (Atomic Procedures)
    //
    // =============================================

    // 原子流程: 更新本地的状态缓存 (符合原子性定义)
    PROCEDURE Atomic_Update_Status_Cache(Target_TN: INTEGER, New_Data: DICTIONARY, Source_TN: INTEGER, Priority: INTEGER) "Updates the local status cache for a specific track." {
        STEPS {
            // 这是一个不可再分的逻辑操作
            ASSIGN Cache_Entry = {
                StatusData= New_Data,
                Source_TN= Source_TN,
                Priority= Priority
            };
            CALL Unit_Status_Cache.set(TN=Target_TN, Data=Cache_Entry);
            STEP "Notify local systems that track status has been updated.";
        }
    }

    // 原子流程: 向操作员发送告警
    PROCEDURE Atomic_Alert_Operator(Recipient: STRING, Message: STRING) "Sends an alert to the operator of a specific actor/system." {
        STEPS {
            STEP Own_Unit NOTIFY Message TO Recipient;
        }
    }
}