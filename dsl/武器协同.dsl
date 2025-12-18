FUNCTION_MODEL Link16_Control_Handover_Detailed {

        // =================================================================
        // 1. 声明块 (Declarations Block)
        // =================================================================

        ACTORS {
                C2_JU_A            : C2_JU;                            // 本机，初始控制单元 (A控)
                C2_JU_B            : C2_JU;                            // 远程单元，新的控制单元 (B控)
                Aircraft           : NON_C2_JU;                    // 被移交的作战平台
                Operator_A       : GENERIC_PLATFORM;       // A控的操作员
                Operator_B       : GENERIC_PLATFORM;       // B控的操作员
        }

        MESSAGES {
                J10.3;           // 切换消息
                J10.5;           // 控制单元报告消息
                J12.4;           // 控制单元变更消息
                J9.0;            // 指挥消息 (用于触发场景c)
                J7.1;            // 数据更新请求消息 (用于场景d.1)
                J13.X;     // 状态信息消息 (用于 J7.1 的回复)
        }

        DISCRETES {
                // R/C (回执/遵从) 字段值
                ENUM RC_Field_Values {
                        Original = 0 "Initial Request";
                        Machine_Receipt = 2 "Machine Receipt";
                        WILCO = 3 "Will Comply";
                        HAVCO = 4 "Have Comply";
                        CANTCO = 6 "Cannot Comply";
                        CANTPRO = 7 "Cannot Comply - Protocol";
                }

                // J10.3 RequestForAssumeControl 字段值(R/C字段)
                ENUM Request_Field_Values {
                        Assume_Control_Request = 0 "Assume Control Request (Not Engaging)";
                        Assume_Control_Engaging = 1 "Assume Control Request (Engaging)";
                        Transfer_Control_Request = 2 "Request for Transfer of Control";
                }

                // J12.4 CCI (控制变更指示) 字段值
                ENUM CCI_Field_Values {
                        Control_Change_Order = 0 "Control Change Order";
                        Control_Request = 1 "Control Request";
                }
                  
                // J10.5 HandoverIndicator (移交指示符) 字段值
                ENUM Handover_Indicator_Values {
                        No_Handover = 0 "No Handover in Progress";
                        Handover_In_Progress = 1 "Handover in Progress";
                }

                // J10.3 CancellationIndicator (取消指示符) 字段值
                ENUM Cancellation_Values {
                        Not_A_Cancellation = 0 "Not a Cancellation Message";
                        Is_A_Cancellation = 1 "Is a Cancellation Message";
                }
        }

        STATES {
                Handover_Active           : BOOLEAN = FALSE; // 跟踪移交流程是否正在进行
                J12_4_Sent_To_Asset : BOOLEAN = FALSE; // 跟踪J12.4是否已发送给作战单元
                Handover_Complete       : BOOLEAN = FALSE; // 跟踪交接是否已完成
        }

        // =================================================================
        // 2. 流程与规则定义块 (Logic Block)
        // =================================================================

        // -----------------------------------------------------------------
        // 第三层: 核心流程 (Core Procedure)   
        // -----------------------------------------------------------------
          
        PROCEDURE Core_Manage_Control_Handover "Manages the entire control handover workflow" {
                // 触发器覆盖了 a, b, c 三种启动场景 和 对于J10.5消息涉及到的TN的更新
        TRIGGER "Operator_A initiates handover" 
                 OR MESSAGE_RECEIVED J10.3(RequestForAssumeControl == Transfer_Control_Request) FROM C2_JU_B
                 OR MESSAGE_RECEIVED J9.0(Command == 20) FROM Operator_B
                 OR MESSAGE_RECEIVED J10.5;// 控制的重复报告
		
                STEPS {
                        // 将原STEPS内容包裹在一个IF块中，以区分处理交接流程和J10.5报告
                        IF "Operator_A initiates handover" OR MESSAGE_RECEIVED J10.3 OR MESSAGE_RECEIVED J9.0 THEN {
                                // 初始化状态变量
                                ASSIGN Handover_Active = TRUE;
                                ASSIGN J12_4_Sent_To_Asset = FALSE;
                                  
                                IF "Operator_A initiates handover" THEN {
                                        // 场景 a: 由当前控制方(A)主动发起移交
                                        CALL Sub_Handle_Assume_Control_Request(Initiator=C2_JU_A, Receiver=C2_JU_B, Asset=Aircraft);
                                }
                                ELSE_IF MESSAGE_RECEIVED J10.3(RequestForAssumeControl == Transfer_Control_Request) FROM C2_JU_B THEN {
                                        // 场景 b: 由新的控制方(B)请求获得控制权
                                        CALL Sub_Handle_Transfer_Control_Request(Requester=C2_JU_B, CurrentController=C2_JU_A, Asset=Aircraft);
                                }
                                ELSE_IF MESSAGE_RECEIVED J9.0(Command == 20) THEN {
                                        // 场景 c: 由上级 J9.0 命令触发移交
                                        CALL Sub_Alert_Operator(Operator=Operator_A, Message="Received J9.0 command to transfer control. Initiating handover.");
                                        // 假设默认执行 场景a 模式
                                        CALL Sub_Handle_Assume_Control_Request(Initiator=C2_JU_A, Receiver=C2_JU_B, Asset=Aircraft);
                                }
                        }
                        // 新增逻辑分支: 如果触发事件是收到J10.5消息   
                        ELSE_IF MESSAGE_RECEIVED J10.5 THEN {
                                // 调用专门的子流程来处理J10.5消息
                                CALL Sub_Process_Incoming_J10_5_Report();
                        }
                }

                // 场景 d.2: 集中处理“取消”异常，区分了取消指令的来源
                EXCEPTION {
                        // 如果从A控收到取消指令
                        ON MESSAGE_RECEIVED J10.3(CancellationIndicator == Is_A_Cancellation) FROM C2_JU_A AND Handover_Active == TRUE THEN {
                                CALL Sub_Handle_Cancellation_By_A();
                        }
                        // 如果从B控收到取消指令
                        ON MESSAGE_RECEIVED J10.3(CancellationIndicator == Is_A_Cancellation) FROM C2_JU_B AND Handover_Active == TRUE THEN {
                                CALL Sub_Handle_Cancellation_By_B();
                        }
                        // 处理特殊情况: 作战单元返回A控
                        ON "Asset returns to A due to contact failure with B" AND Handover_Active == TRUE THEN {
                                ASSIGN Handover_Active = FALSE;
                                CALL Sub_Alert_Operator(Operator=Operator_A, Message="Asset returned due to contact failure with B. Sending cancellation to terminate the process formally.");
                                // A控发送一条J10.3取消消息给B控，以正式终结悬停的交接流程
                                CALL Sub_SendMessage(
                                        Sender = C2_JU_A,
                                        MessageType = "J10.3",
                                        // [FORMATTED]
                                        Params = {
                        AddresseeTN = C2_JU_B.TN,
                        RC = Original,
                        ReferenceTN = Aircraft.TN,
                        CancellationIndicator = Is_A_Cancellation
                    },
                                        Mode = "SEND",
                                        Recipient = C2_JU_B,
                                        ToAddress = NULL
                                );
                                TERMINATE;
                        }
                }
        }

        // -----------------------------------------------------------------
        // 第二层: 子流程 (Sub-procedures)   
        // -----------------------------------------------------------------

        // 子流程: 发送战术消息 (新增的通用流程)
        // 描述: 一个通用的、可复用的消息发送接口，用于发送或广播指定类型的战术消息。
        // 参数: Sender - 发送方, MessageType - 消息类型 (如 "J7.0"), Params - 消息内容 (字典/结构体), Mode - 模式 ("SEND", "BROADCAST", "BROADCAST_TO_ADDRESS"), Recipient - 接收方 (用于SENDS), ToAddress - 目标地址 (用于BROADCAST_TO_ADDRESS)
        PROCEDURE Sub_SendMessage(Sender: STRING, MessageType: STRING, Params: DICTIONARY, Mode: STRING, Recipient: STRING, ToAddress: STRING) "A generic sub-procedure to send or broadcast a tactical message." {
                STEPS {
                        IF Mode == "SEND" THEN {
                                STEP Sender SENDS MessageType(Params=Params) TO Recipient;
                        }
                        ELSE_IF Mode == "BROADCAST_TO_ADDRESS" THEN {
                                STEP Sender BROADCASTS MessageType(Params=Params) TO_ADDRESS ToAddress;
                        }
                        ELSE { // 默认为 "BROADCAST"
                                STEP Sender BROADCASTS MessageType(Params=Params);
                        }
                }
        }

        // 子流程: 告警操作员 (L2封装L1)
        // 描述: 封装了 "Atomic_Alert_Operator" 的L1原子流程，以满足L3->L2的调用规则。
        PROCEDURE Sub_Alert_Operator(Operator: STRING, Message: STRING) "Encapsulates the atomic alert operation" {
                STEPS {
                        CALL Atomic_Alert_Operator(Operator=Operator, Message=Message);
                }
        }

        // 子流程 a: 处理"请求承担控制"
        PROCEDURE Sub_Handle_Assume_Control_Request(Initiator: STRING, Receiver: STRING, Asset: STRING) "Handles the 'Request for Assume Control' sequence (a)" {
                STEPS {
                        // 阶段一，第一步: A控发送交接请求
                        CALL Sub_SendMessage(
                                Sender = Initiator,
                                MessageType = "J10.3",
                                // [FORMATTED]
                                Params = {
                    AddresseeTN = Receiver.TN,
                    RC = Original,
                    RequestForAssumeControl = Assume_Control_Request,
                    ReferenceTN = Asset.TN,
                    CancellationIndicator = Not_A_Cancellation
                },
                                Mode = "SEND",
                                Recipient = Receiver,
                                ToAddress = NULL
                        );
                          
                        // 阶段一，第二步: 等待 B控 的机器回执
                        WAIT FOR 10 SECONDS {
                                ON MESSAGE_RECEIVED J10.3(RC == Machine_Receipt) FROM Receiver THEN {
                                        // 阶段一，第三步: 收到机器回执后，告警B控操作员并等待其人工响应
                                        CALL Atomic_Alert_Operator(Operator=Operator_B, Message="Incoming handover request. Please decide.");
                                          
                                        // 场景 d.1: B控可在同意前选择性请求平台状态信息
                                        IF "Operator_B needs status info" THEN {
                                                CALL Sub_SendMessage(
                                                        Sender = Receiver,
                                                        MessageType = "J7.1",
                                                        // [FORMATTED] Empty Params
                                                        Params = {
                                                        },
                                                        Mode = "SEND",
                                                        Recipient = Initiator,
                                                        ToAddress = NULL
                                                );
                                                WAIT FOR 20 SECONDS {
                                                        ON MESSAGE_RECEIVED J13.X FROM Initiator THEN {
                                                                STEP "Process status info";
                                                        }
                                                }
                                        }

                                        // 等待B控的人工决策（同意/拒绝）
                                        WAIT FOR 60 SECONDS {
                                                // 收到同意 WILCO
                                                ON MESSAGE_RECEIVED J10.3(RC == WILCO) FROM Receiver THEN {
                                                        // 阶段一，第四步: A控回复机器回执，确认收到“同意”指令
                                                        CALL Sub_SendMessage(
                                                                Sender = Initiator,
                                                                MessageType = "J10.3",
                                                                // [FORMATTED]
                                                                Params = {
                                    AddresseeTN = Receiver.TN,
                                    RC = Machine_Receipt,
                                    RequestForAssumeControl = Assume_Control_Request,
                                    ReferenceTN = Asset.TN,
                                    CancellationIndicator = Not_A_Cancellation
                                },
                                                                Mode = "SEND",
                                                                Recipient = Receiver,
                                                                ToAddress = NULL
                                                        );
                                                        // 进入阶段二
                                                        CALL Sub_Execute_Digital_Handshake(ControllerA=Initiator, ControllerB=Receiver, Asset=Asset);
                                                }
                                                // 收到不同意 CONTCO
                                                ON MESSAGE_RECEIVED J10.3(RC == CANTCO) FROM Receiver THEN {
                                                        CALL Atomic_Alert_Operator(Operator=Operator_A, Message="Handover rejected by remote unit (CANTCO).");
                                                        TERMINATE;
                                                }
                                                // 场景 d.3: 处理超时和CANTPRO
                                                ON MESSAGE_RECEIVED J10.3(RC == CANTPRO) FROM Receiver OR TIMEOUT THEN {
                            CALL Atomic_Alert_Operator(Operator=Operator_A, Message="Handover failed: No valid response or protocol error. Voice coordination may be required.");
                            TERMINATE;
                                                }
                                        }
                                }
                                // 如果机器回执超时
                                ON TIMEOUT THEN {
                                        CALL Atomic_Alert_Operator(Operator=Operator_A, Message="Handover failed: Did not receive machine receipt from remote unit.");
                                        TERMINATE;
                                }
                        }
                }
        }

        // 子流程 b: 处理"请求转移控制"   
        PROCEDURE Sub_Handle_Transfer_Control_Request(Requester: STRING, CurrentController: STRING, Asset: STRING) "Handles the 'Request for Transfer of Control' sequence (b)" {
                STEPS {
                        // 阶段二: A控操作员决策，人机交互，操作员决策，所以使用USER_CONFIRM
                        //如果A控操作员希望协商，会在发送任何回复（WILCO或CANTCO）之前，通过语音通信与B控进行协调   
                        USER_CONFIRM "Accept transfer control request from remote unit?" THEN {
                                // A控同意: 回复WILCO并启动数字切换
                                CALL Sub_SendMessage(
                                        Sender = CurrentController,
                                        MessageType = "J10.3",
                                        // [FORMATTED]
                                        Params = {
                        AddresseeTN = Requester.TN,
                        RC = WILCO,
                        RequestForAssumeControl = Transfer_Control_Request,
                        ReferenceTN = Asset.TN,
                        CancellationIndicator = Not_A_Cancellation
                    },
                                        Mode = "SEND",
                                        Recipient = Requester,
                                        ToAddress = NULL
                                );
                                CALL Sub_Execute_Digital_Handshake(ControllerA=CurrentController, ControllerB=Requester, Asset=Asset);
                        }
                        ELSE {
                                // A控拒绝: 回复CANTCO，流程终止
                                CALL Sub_SendMessage(
                                        Sender = CurrentController,
                                        MessageType = "J10.3",
                                        // [FORMATTED]
                                        Params = {
                        AddresseeTN = Requester.TN,
                        RC = CANTCO,
                        RequestForAssumeControl = Transfer_Control_Request,
                        ReferenceTN = Asset.TN,
                        CancellationIndicator = Not_A_Cancellation
                    },
                                        Mode = "SEND",
                                        Recipient = Requester,
                                        ToAddress = NULL
                                );
                                TERMINATE;
                        }
                }
        }

        // 子流程: 执行阶段二和三的数字对接
        PROCEDURE Sub_Execute_Digital_Handshake(ControllerA: STRING, ControllerB: STRING, Asset: STRING) "Executes the digital handshake with the asset and network" {
                STEPS {
                        // 阶段二，第5步: A控向作战单元下达J12.4变更命令
                        CALL Sub_SendMessage(
                                Sender = ControllerA,
                                MessageType = "J12.4",
                                // [FORMATTED]
                                Params = {
                    AddresseeTN = Asset.TN,
                    RC = Original,
                    CCI = Control_Change_Order,
                    NewControllerTN = ControllerB.TN
                },
                                Mode = "SEND",
                                Recipient = Asset,
                                ToAddress = NULL
                        );
                        ASSIGN J12_4_Sent_To_Asset = TRUE;
                          
                        // 阶段二，第6步(前半): 等待作战单元响应
                        WAIT FOR 10 SECONDS {
                                ON MESSAGE_RECEIVED J12.4(RC == Machine_Receipt) FROM Asset THEN {
                                        // 收到机器回执后，再等待其“遵从”响应 (WILCO/CANTCO)
                                        WAIT FOR 30 SECONDS {
                                                ON MESSAGE_RECEIVED J12.4(RC == WILCO) FROM Asset THEN {
                                                        // A控回复机器回执，确认收到作战单元的WILCO
                                                        CALL Sub_SendMessage(
                                                                Sender = ControllerA,
                                                                MessageType = "J12.4",
                                                                // [FORMATTED]
                                                                Params = {
                                                                        AddresseeTN = Asset.TN,
                                                                        RC = Machine_Receipt,
                                                                        CCI = Control_Change_Order
                                                                },
                                                                Mode = "SEND",
                                                                Recipient = Asset,
                                                                ToAddress = NULL
                                                        );

                                                        // 阶段三，广播状态: A控收到WILCO后，立即广播"交接中"
                                                        CALL Sub_SendMessage(
                                                                Sender = ControllerA,
                                                                MessageType = "J10.5",
                                                                // [FORMATTED]
                                                                Params = {
                                    ReferenceTN = Asset.TN,
                                    HandoverIndicator = Handover_In_Progress
                                },
                                                                Mode = "BROADCAST",
                                                                Recipient = NULL,
                                                                ToAddress = NULL
                                                        );
                                                          
                                                        // 阶段二，第6步(后半): 作战单元周期性联系B控
                                                        PARALLEL {
                                                                BRANCH {
                                                                        ASSIGN attempts = 0;
                                                                        ASSIGN responded = FALSE;
                                                                        // 作战单元会周期性发送请求，直到收到B控响应
                                                                        WHILE attempts < 3 AND responded == FALSE DO {
                                                                                CALL Sub_SendMessage(
                                                                                        Sender = Asset,
                                                                                        MessageType = "J12.4",
                                                                                        // [FORMATTED]
                                                                                        Params = {
                                                CCI = Control_Request,
                                                AddresseeTN = ControllerB.TN
                                            },
                                                                                        Mode = "SEND",
                                                                                        Recipient = ControllerB,
                                                                                        ToAddress = NULL
                                                                                );
                                                                                WAIT FOR 12 SECONDS {
                                                                                        ON MESSAGE_RECEIVED J12.4 FROM ControllerB THEN {
                                                                                                ASSIGN responded = TRUE;
                                                                                        }
                                                                                        ON TIMEOUT THEN {
                                                                                                ASSIGN attempts = attempts + 1;
                                                                                        }
                                                                                }
                                                                        }
                                                                }
                                                                BRANCH {
                                                                        // 阶段二，第7步: B控确认接管
                                                                        WAIT {
                                                                                ON MESSAGE_RECEIVED J12.4(CciValue==Control_Request) FROM Asset THEN {
                                                                                        // B控回复机器回执和HAVCO
                                                                                        CALL Sub_SendMessage(
                                                                                                Sender = ControllerB,
                                                                                                MessageType = "J12.4",
                                                                                                // [FORMATTED]
                                                                                               Params = {
                                                    AddresseeTN = Asset.TN,
                                                    RC = Machine_Receipt,
                                                    CCI = Control_Request
                                                },
                                                                                                Mode = "SEND",
                                                                                                Recipient = Asset,
                                                                                                ToAddress = NULL
                                                                                        );
                                                                                        CALL Sub_SendMessage(
                                                                                                Sender = ControllerB,
                                                                                                MessageType = "J12.4",
                                                                                                // [FORMATTED]
                                                                                                Params = {
                                                    AddresseeTN = Asset.TN,
                                                    RC = HAVCO,
                                                    CCI = Control_Request
                                                },
                                                                                                Mode = "SEND",
                                                                                                Recipient = Asset,
                                                                                                ToAddress = NULL
                                                                                        );

                                                                                        // B控等待作战单元对HAVCO的最终机器回执
                                                                                        WAIT FOR 10 SECONDS {
                                                                                                ON MESSAGE_RECEIVED J12.4(RC == Machine_Receipt) FROM Asset THEN {
                                                                                                        // 收到最终回执，数字握手完成，B控正式接管
                                                                                                        // 阶段三，广播状态: B控正式接管，广播"我已控制"
                                                                                                        CALL Sub_SendMessage(
                                                                                                                Sender = ControllerB,
                                                                                                                MessageType = "J10.5",
                                                                                                                // [FORMATTED]
                                                                                                                Params = {
                                                            ReferenceTN = Asset.TN,
                                                            HandoverIndicator = No_Handover
                                                        },
                                                                                                                Mode = "BROADCAST",
                                                                                                                Recipient = NULL,
                                                                                                                ToAddress = NULL
                                                                                                        );
          
                                                                                                        // 阶段三，最后一步: A控监测到B的报告后停止广播
                                                                                                        WAIT FOR 30 SECONDS {
                                                                                                                ON MESSAGE_RECEIVED J10.5 FROM ControllerB THEN {
                                                                                                                        CALL Atomic_Stop_J10_5_Broadcast(Unit=ControllerA, Asset=Asset);
                                                                                                                        // 标记交接已完成
                                                                                                                        ASSIGN Handover_Complete = TRUE;
                                                                                                                        ASSIGN Handover_Active = FALSE;
                                                                                                                }
                                                                                                        }
                                                                                                }
                                                                                                ON TIMEOUT THEN {
                                                                                                        CALL Atomic_Alert_Operator(Operator=Operator_B, Message="Handover failed: Did not receive final machine receipt from asset.");
                                                                                                        TERMINATE;
                                                                                                }
                                                                                        }
                                                                                }
                                                                        }
                                                                }
                                                        }
                                                }
                                                ON MESSAGE_RECEIVED J12.4(RC IN (CANTCO, CANTPRO)) FROM Asset THEN {
                                                        // 作战单元拒绝变更，A控将保留指挥权
                                                        CALL Atomic_Alert_Operator(Operator=Operator_A, Message="Asset rejected control change. Cancelling handover.");
                                                        CALL Sub_SendMessage(
                                                                Sender = ControllerA,
                                                                MessageType = "J10.3",
                                                                // [FORMATTED]
                                                                Params = {
                                                                        AddresseeTN = ControllerB.TN,
                                                                        RC = Original,
                                                                        ReferenceTN = Asset.TN,
                                                                        CancellationIndicator = Is_A_Cancellation
                                                                },
                                                                Mode = "SEND",
                                                                Recipient = ControllerB,
                                                                ToAddress = NULL
                                                        );
                                                        TERMINATE;
                                                }
                                                ON TIMEOUT THEN {
                                                        CALL Atomic_Alert_Operator(Operator=Operator_A, Message="Handover failed: Asset sent machine receipt but did not send WILCO/CANTCO.");
                                                        TERMINATE;
                                                }
                                        }
                                }
                                ON TIMEOUT THEN {
                                        CALL Atomic_Alert_Operator(Operator=Operator_A, Message="Handover failed: Did not receive machine receipt from asset for control change order.");
                                        TERMINATE;
                                }
                        }
                }
        }

          
        // 取消交接
        // 场景一 (A控取消)   
        PROCEDURE Sub_Handle_Cancellation_By_A "Handles cancellation initiated by Controller A" {
                STEPS {
                        // 关键逻辑: 检查交接是否已经完成
                        IF Handover_Complete == FALSE THEN {
                                // 条件一: 交接还未完成，可以正常取消
                                // DSL的EXCEPTION机制会中断原流程，这本身就实现了“阻止J12.4发送”的效果
                                ASSIGN Handover_Active = FALSE;
                                CALL Atomic_Alert_Operator(Operator=Operator_A, Message="Cancellation successful. Handover process terminated.");
                                CALL Atomic_Alert_Operator(Operator=Operator_B, Message="Handover has been cancelled by the initiating unit (A).");
                                TERMINATE;
                        }
                        ELSE {
                                // 条件二: 交接已经完成，不能使用“取消”功能
                                // 系统应向A控操作员提示，当前操作无效
                                CALL Atomic_Alert_Operator(Operator=Operator_A, Message="Invalid action: Handover is already complete. To regain control, you must initiate a new 'Request for Transfer of Control'.");
                                // 流程终止，不执行任何取消动作
                                TERMINATE;
                        }
                }
        }

        // 场景二 (B控取消)   
        PROCEDURE Sub_Handle_Cancellation_By_B "Handles cancellation initiated by Controller B" {
                STEPS {
                        // 第一层检查: 交接是否已经完成
                        IF Handover_Complete == TRUE THEN {
                                // 情况一: 交接已完成，B控不能使用“取消”，必须发起新的“交接请求”
                                CALL Atomic_Alert_Operator(Operator=Operator_B, Message="Invalid action: Handover is already complete. To return control, you must initiate a new 'Request for Assume Control'.");
                                TERMINATE;
                        }
                        ELSE {
                                // 第二层检查: J12.4是否已发送
                                IF J12_4_Sent_To_Asset == FALSE THEN {
                                        // 情况二: 交接未完成，且J12.4还未发送，可以正常取消
                                        ASSIGN Handover_Active = FALSE;
                                        CALL Atomic_Alert_Operator(Operator=Operator_A, Message="Handover has been successfully cancelled by the receiving unit (B).");
                                        TERMINATE;
                                }
                                ELSE {
                                        // 情况三: 交接未完成，但J12.4已发送，取消为时已晚
                                        CALL Atomic_Alert_Operator(Operator=Operator_A, Message="Cancellation from B received too late. Replying with CANTPRO as per protocol.");
                                        // A控必须回复CANTPRO，B控则必须完成这次控制权转移
                                        CALL Sub_SendMessage(
                                                Sender = C2_JU_A,
                                                MessageType = "J10.3",
                                                // [FORMATTED]
                                                Params = {
                            RC = CANTPRO,
                            AddresseeTN = C2_JU_B.TN
                        },
                                                Mode = "SEND",
                                                Recipient = C2_JU_B,
                                                ToAddress = NULL
                                        );
                                        TERMINATE;
                                }
                        }
                }
        }

        // 子流程: 处理传入的J10.5消息并检查控制权冲突
        PROCEDURE Sub_Process_Incoming_J10_5_Report "Processes an incoming J10.5 report for duplicate control" {
                STEPS {
                        // 检查当前航迹的已知控制方是否与新消息的来源方不同
                        // 注意: GET_CONTROLLER_FOR 和 J10.5.SourceTN 均为示意，实际实现需从消息和数据库中获取
                        IF GET_CONTROLLER_FOR(ReferenceTN=J10_5.ReferenceTN) != J10_5.SourceTN THEN {
                                // 如果不同，则接受最新的源TN作为新的控制方
                                CALL Atomic_Update_Controller_For_Track(TN=J10_5.ReferenceTN, NewController=J10_5.SourceTN);
                                CALL Atomic_Alert_Operator(Operator=Operator_A, Message="Control for track " + J10_5.ReferenceTN + " updated to new C2 JU " + J10_5.SourceTN + " based on latest J10.5 report.");
                        }
                }
        }
          
        // -----------------------------------------------------------------
        // 第一层: 原子流程 (Atomic Procedures)
        // -----------------------------------------------------------------
          
        // [REMOVED] Atomic_Send_J10_3 (已被 Sub_SendMessage 替代)
        // [REMOVED] Atomic_Send_J12_4 (已被 Sub_SendMessage 替代)
        // [REMOVED] Atomic_Broadcast_J10_5 (已被 Sub_SendMessage 替代)
          
        PROCEDURE Atomic_Alert_Operator(Operator: STRING, Message: STRING) "Alerts a human operator" {
                STEPS {
                        STEP C2_JU_A NOTIFY Message TO Operator;
                }
        }

        PROCEDURE Atomic_Stop_J10_5_Broadcast(Unit: STRING, Asset: STRING) "Ceases the periodic broadcast of J10.5 for an asset" {
                STEPS {
                        STEP NATURAL_LANGUAGE {
                                INTENT "Cease periodic J10.5 transmission.";
                                DESCRIPTION "The specified unit stops its periodic J10.5 broadcast for the given asset, finalizing the handover.";
                        };
                }
        }
          
        // 原子流程: 获取指定航迹的当前控制方 (通过自然语言模拟)
        PROCEDURE Atomic_Get_Controller_For_Track(TN: INTEGER) "Gets the current controller for a given track" {
                STEPS {
                        STEP NATURAL_LANGUAGE {
                                INTENT "Query local track database for current controller.";
                                DESCRIPTION "The system retrieves the currently assigned controller's TN for the given reference track TN from its local database.";
                        };
                }
        }
          
        // 原子流程: 更新指定航迹的控制方 (通过自然语言模拟)
        PROCEDURE Atomic_Update_Controller_For_Track(TN: INTEGER, NewController: STRING) "Updates the controller for a given track" {
                STEPS {
                        STEP NATURAL_LANGUAGE {
                                INTENT "Update the controller in the local track database.";
                                DESCRIPTION "The system updates its local database, assigning the NewController as the controlling C2 JU for the specified track TN.";
                        };
                }
        }
}