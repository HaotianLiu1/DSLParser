FUNCTION_MODEL Link16_Control_Change_Procedures {

    // =================================================================
    // 1. 声明块 (Declarations Block)
    // =================================================================

    ACTORS {
        // --- 参与者定义 ---
        C2_JU_A               : C2_JU;              // C2单元 'A', 在“启动”场景中是发起方, 在“移交”场景中是原控制方
        C2_JU_B               : C2_JU;              // C2单元 'B', 在“移交”场景中是新控制方
        Aircraft              : NON_C2_JU;          // 非指挥控制单元 (作战飞机)
        Operator_A            : GENERIC_PLATFORM;   // A控的操作员
        Operator_B            : GENERIC_PLATFORM;   // B控的操作员
        Aircraft_Operator     : GENERIC_PLATFORM;   // 作战飞机的操作员 (例如, 飞行员)
    }

    MESSAGES {
        J12.4;  // 控制单元变更消息
        J0.3;   // 时隙重分配命令消息
        // 注意: J10.3 等移交专用消息不再需要在此处声明, 因为所有发送逻辑都封装在被调用的外部模型中。
    }

    DISCRETES {
        // R/C (回执/遵从) 字段值
        ENUM RC_Field_Values {
            Original_Order_Req_Response = 0 "Initial Order, Response Required";
            Broadcast_Request           = 1 "Broadcast Request";
            Machine_Receipt             = 2 "Machine Receipt";
            WILCO                       = 3 "Will Comply";
            HAVCO                       = 4 "Have Comply";
            CANTCO                      = 6 "Cannot Comply (Operator Decision)";
            CANTPRO                     = 7 "Cannot Comply (Protocol/System Error)";
        }

        // CCI (控制变更指示) 字段值
        ENUM CCI_Field_Values {
            Control_Change_Order = 0 "Control Change Order";
            Control_Request      = 1 "Control Request";
            Terminate_Control    = 2 "Terminate Control";
        }
    }

    STATES {
        Control_Established: BOOLEAN = FALSE; // 跟踪控制关系是否已成功建立
    }

    // =================================================================
    // 3. 核心流程 (Core Procedure)
    // =================================================================
    PROCEDURE Core_Manage_Control_Procedures "Top-level procedure to manage both initiation and handover of control by calling appropriate sub-procedures." {

        // 核心流程的触发器, 覆盖了“启动”、“移交”和“终止”三种场景
        TRIGGER "Operator_A initiates control initiation"
                 OR "Aircraft_Operator initiates control request"
                 OR "Operator_A initiates handover"
                 OR "Operator_A initiates control termination";
         
        STEPS {
            // 根据具体的触发事件来决定调用哪个子流程
            IF "Event was Operator_A initiates control initiation" THEN {
                // 场景 a.1: C2 JU 发起控制启动
                CALL Sub_C2_JU_Initiated_Handshake(Initiator=C2_JU_A, Target=Aircraft);
            }
            ELSE_IF "Event was Aircraft_Operator initiates control request" THEN {
                // 场景 a.2: NON C2 JU 发起控制启动
                USER_CONFIRM "Does the aircraft know the specific C2 JU to contact?" THEN {
                    CALL Sub_Non_C2_JU_Known_Target_Request(Requester=Aircraft, Target=C2_JU_A);
                }
                ELSE {
                    CALL Sub_Non_C2_JU_Broadcast_Request(Requester=Aircraft);
                }
            }
            ELSE_IF "Event was Operator_A initiates handover" THEN {
                // 场景 b: C2 JU A 启动控制权移交
                CALL Link16_Control_Handover_Detailed.Sub_Handle_Assume_Control_Request(
                    Initiator=C2_JU_A, 
                    Receiver=C2_JU_B, 
                    Asset=Aircraft
                );
            }
            ELSE_IF "Event was Operator_A initiates control termination" THEN {
                // 场景 c: C2 JU A 启动控制权终止
                CALL Sub_Terminate_Control(Controller=C2_JU_A, Asset=Aircraft);
            }
        }
    }

	// =================================================================
            // 2. 子流程 (Sub-procedures) - 仅包含控制启动和终止相关流程
            // =================================================================

            // 子流程 1: C2 JU 发起控制
            PROCEDURE Sub_C2_JU_Initiated_Handshake(Initiator: STRING, Target: STRING) "Handles the control initiation handshake started by a C2 JU." {
                        STEPS {
                                    // 阶段一，步骤 1: C2 JU 发送初始命令 (CCI=0)
                                    // [MODIFIED] 调用通用发送子流程
                                    CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                                                Sender = Initiator,
                                                MessageType = "J12.4",
                                                Params = {
                                                            RC = Original_Order_Req_Response,
                                                            CCI = Control_Change_Order
                                                },
                                                Mode = "SEND",
                                                Recipient = Target,
                                                ToAddress = NULL
                                    );

                                    // C2 JU 等待 Aircraft 的响应
                                    WAIT FOR 10 SECONDS {
                                                ON MESSAGE_RECEIVED J12.4(RC == Machine_Receipt) FROM Target THEN {
                                                            WAIT FOR 60 SECONDS {
                                                                        ON MESSAGE_RECEIVED J12.4(RC == WILCO) FROM Target THEN {
                                                                                    // [MODIFIED] 调用通用发送子流程 (回复机器回执)
                                                                                    CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                                                                                                Sender = Initiator,
                                                                                                MessageType = "J12.4",
                                                                                                Params = {
                                                                                                            RC = Machine_Receipt
                                                                                                            // CCI 字段可能不需要在此回复中
                                                                                                },
                                                                                                Mode = "SEND",
                                                                                                Recipient = Target,
                                                                                                ToAddress = NULL
                                                                                    );
                                                                        }
                                                                        ON MESSAGE_RECEIVED J12.4(RC IN (CANTCO, CANTPRO)) FROM Target THEN {
                                                                                    CALL Atomic_Alert_Operator(Recipient=Operator_A, Message="Failure: Aircraft rejected the control order.");
                                                                                    TERMINATE;
                                                                        }
                                                                        ON TIMEOUT THEN {
                                                                                    CALL Atomic_Alert_Operator(Recipient=Operator_A, Message="Failure: Timed out waiting for WILCO/CANTCO from aircraft.");
                                                                                    TERMINATE;
                                                                        }
                                                            }
                                                }
                                                ON TIMEOUT THEN {
                                                            CALL Atomic_Alert_Operator(Recipient=Operator_A, Message="Failure: Did not receive initial machine receipt from aircraft.");
                                                            TERMINATE;
                                                }
                                    }

                                    // 阶段二: C2 JU 等待 Aircraft 在新信道上发送 Control Request (CCI=1)
                                    WAIT FOR 20 SECONDS {
                                                ON MESSAGE_RECEIVED J12.4(CCI == Control_Request) FROM Target THEN {
                                                            // [MODIFIED] 调用通用发送子流程 (回复机器回执)
                                                            CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                                                                        Sender = Initiator,
                                                                        MessageType = "J12.4",
                                                                        Params = {
                                                                                    RC = Machine_Receipt
                                                                                    // CCI 字段可能不需要在此回复中
                                                                        },
                                                                        Mode = "SEND",
                                                                        Recipient = Target,
                                                                        ToAddress = NULL
                                                            );
                                                            CALL Sub_Handle_Optional_Timeslot_Assignment(Controller=Initiator, Aircraft=Target);
                                                            // [MODIFIED] 调用通用发送子流程 (回复 HAVCO)
                                                            CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                                                                        Sender = Initiator,
                                                                        MessageType = "J12.4",
                                                                        Params = {
                                                                                    RC = HAVCO
                                                                                    // CCI 字段可能不需要在此回复中
                                                                        },
                                                                        Mode = "SEND",
                                                                        Recipient = Target,
                                                                        ToAddress = NULL
                                                            );
                                                            WAIT FOR 10 SECONDS {
                                                                        ON MESSAGE_RECEIVED J12.4(RC == Machine_Receipt) FROM Target THEN {
                                                                                    ASSIGN Control_Established = TRUE;
                                                                                    CALL Atomic_Alert_Operator(Recipient=Operator_A, Message="Control relationship successfully established.");
                                                                        }
                                                                        ON TIMEOUT THEN {
                                                                                    CALL Atomic_Alert_Operator(Recipient=Operator_A, Message="Failure: Did not receive final machine receipt for HAVCO.");
                                                                                    TERMINATE;
                                                                        }
                                                            }
                                                }
                                                ON TIMEOUT THEN {
                                                            CALL Atomic_Alert_Operator(Recipient=Operator_A, Message="Failure: Did not receive Control Request from aircraft.");
                                                            TERMINATE;
                                                }
                                    }
                        }
            }

            // 子流程 2: non-C2 JU 发起控制 (知道目标)
            PROCEDURE Sub_Non_C2_JU_Known_Target_Request(Requester: STRING, Target: STRING) "Handles the request when a Non-C2 JU contacts a known C2 JU." {
                        STEPS {
                                    // [MODIFIED] 调用通用发送子流程 (发送初始请求)
                                    CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                                                Sender = Requester,
                                                MessageType = "J12.4",
                                                Params = {
                                                            RC = Original_Order_Req_Response,
                                                            CCI = Control_Request
                                                },
                                                Mode = "SEND",
                                                Recipient = Target,
                                                ToAddress = NULL
                                    );
                                    WAIT FOR 30 SECONDS {
                                                ON MESSAGE_RECEIVED J12.4(RC == Machine_Receipt) FROM Target THEN {
                                                            CALL Sub_Handle_Optional_Timeslot_Assignment(Controller=Target, Aircraft=Requester);
                                                            WAIT FOR 60 SECONDS {
                                                                        ON MESSAGE_RECEIVED J12.4(RC IN (WILCO, HAVCO)) FROM Target THEN {
                                                                                    // [MODIFIED] 调用通用发送子流程 (回复机器回执)
                                                                                    CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                                                                                                Sender = Requester,
                                                                                                MessageType = "J12.4",
                                                                                                Params = {
                                                                                                            RC = Machine_Receipt
                                                                                                },
                                                                                                Mode = "SEND",
                                                                                                Recipient = Target,
                                                                                                ToAddress = NULL
                                                                                    );
                                                                                    ASSIGN Control_Established = TRUE;
                                                                                    CALL Atomic_Alert_Operator(Recipient=Aircraft_Operator, Message="Control relationship successfully established.");
                                                                        }
                                                                        ON MESSAGE_RECEIVED J12.4(RC IN (CANTCO, CANTPRO)) FROM Target THEN {
                                                                                    // [MODIFIED] 调用通用发送子流程 (回复机器回执)
                                                                                    CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                                                                                                Sender = Requester,
                                                                                                MessageType = "J12.4",
                                                                                                Params = {
                                                                                                            RC = Machine_Receipt
                                                                                                },
                                                                                                Mode = "SEND",
                                                                                                Recipient = Target,
                                                                                                ToAddress = NULL
                                                                                    );
                                                                                    CALL Atomic_Alert_Operator(Recipient=Aircraft_Operator, Message="Request failed: Target C2 JU rejected the control request.");
                                                                                    TERMINATE;
                                                                        }
                                                                        ON TIMEOUT THEN {
                                                                                    CALL Atomic_Alert_Operator(Recipient=Aircraft_Operator, Message="Request failed: Timed out waiting for WILCO/CANTCO.");
                                                                                    TERMINATE;
                                                                        }
                                                            }
                                                }
                                                ON TIMEOUT THEN {
                                                            CALL Atomic_Alert_Operator(Recipient=Aircraft_Operator, Message="Request failed: Did not receive machine receipt from C2 JU.");
                                                            TERMINATE;
                                                }
                                    }
                        }
            }

            // 子流程 3: non-C2 JU 发起控制 (不知道目标)
            PROCEDURE Sub_Non_C2_JU_Broadcast_Request(Requester: STRING) "Handles the broadcast request when a Non-C2 JU does not know which C2 JU to contact." {
                        STEPS {
                                    ASSIGN broadcast_attempts = 0;
                                    WHILE Control_Established == FALSE AND broadcast_attempts < 5 DO {
                                                // [MODIFIED] 调用通用发送子流程 (广播 J12.4 请求)
                                                CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                                                            Sender = Requester,
                                                            MessageType = "J12.4",
                                                            Params = {
                                                                        RC = Broadcast_Request,
                                                                        CCI = Control_Request
                                                            },
                                                            Mode = "BROADCAST_TO_ADDRESS", // 定向广播到特定地址
                                                            Recipient = NULL,
                                                            ToAddress = 00177 // 原原子流程中指定的地址
                                                );
                                                ASSIGN broadcast_attempts = broadcast_attempts + 1;
                                                WAIT FOR 12 SECONDS {
                                                            ON MESSAGE_RECEIVED J12.4(CCI == Control_Change_Order) FROM C2_JU_A THEN {
                                                                        CALL Atomic_Alert_Operator(Recipient=Aircraft_Operator, Message="Broadcast request answered. Transitioning to C2-initiated handshake.");
                                                                        // 跳转到 C2 发起的握手流程
                                                                        CALL Sub_C2_JU_Initiated_Handshake(Initiator=C2_JU_A, Target=Requester);
                                                            }
                                                            ON TIMEOUT THEN {
                                                                        STEP "No response to broadcast, will try again.";
                                                            }
                                                }
                                    }
                                    IF Control_Established == FALSE THEN {
                                                CALL Atomic_Alert_Operator(Recipient=Aircraft_Operator, Message="Request failed: No C2 JU responded to the broadcast request after multiple attempts.");
                                                TERMINATE;
                                    }
                        }
            }
                
            // 可选时隙分配子流程
            PROCEDURE Sub_Handle_Optional_Timeslot_Assignment(Controller: STRING, Aircraft: STRING) "Handles the optional J0.3 timeslot assignment sequence." {
                        STEPS {
                                    IF "Controller supports and requires J0.3 timeslot assignment" THEN {
                                                // [MODIFIED] 调用通用发送子流程 (发送 J0.3)
                                                CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                                                            Sender = Controller,
                                                            MessageType = "J0.3",
                                                            Params = {
                                                                        // J0.3 可能有参数，根据实际情况添加
                                                            },
                                                            Mode = "SEND",
                                                            Recipient = Aircraft,
                                                            ToAddress = NULL
                                                );
                                                WAIT FOR 10 SECONDS {
                                                            ON MESSAGE_RECEIVED J0.3(RC == Machine_Receipt) FROM Aircraft THEN {
                                                                        STEP "J0.3 acknowledged, proceeding.";
                                                            }
                                                            ON MESSAGE_RECEIVED J0.3(RC == CANTPRO) FROM Aircraft THEN {
                                                                        CALL Atomic_Alert_Operator(Recipient=Operator_A, Message="J0.3 failed (CANTPRO). Control handshake may need to be aborted.");
                                                                        TERMINATE;     
                                                            }
                                                            ON TIMEOUT THEN {
                                                                        CALL Atomic_Alert_Operator(Recipient=Operator_A, Message="J0.3 response timed out.");
                                                                        TERMINATE;     
                                                            }
                                                }
                                    }
                        }
            }
                
                
            // “控制终止”子流程
            PROCEDURE Sub_Terminate_Control(Controller: STRING, Asset: STRING) "Handles the 'Termination of Control' sequence (c)." {

                        STEPS {
                                    // 步骤 1: 控制方(Controller)发送J12.4终止命令
                                    CALL Atomic_Alert_Operator(Recipient=Operator_A, Message="Initiating control termination for asset.");
                                    // [MODIFIED] 调用通用发送子流程
                                    CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                                                Sender = Controller,
                                                MessageType = "J12.4",
                                                Params = {
                                                            RC = Original_Order_Req_Response,
                                                            CCI = Terminate_Control
                                                },
                                                Mode = "SEND",
                                                Recipient = Asset,
                                                ToAddress = NULL
                                    );

                                    // 步骤 2: 等待并处理作战单元(Asset)的响应
                                    WAIT FOR 15 SECONDS {
                                                // 成功场景: 收到机器回执
                                                ON MESSAGE_RECEIVED J12.4(RC == Machine_Receipt) FROM Asset THEN {
                                                            ASSIGN Control_Established = FALSE;
                                                            CALL Atomic_Alert_Operator(Recipient=Operator_A, Message="Control successfully terminated.");
                                                            TERMINATE; // 流程正常结束
                                                }
                                                    
                                                // 失败场景 1: 作战单元明确拒绝
                                                ON MESSAGE_RECEIVED J12.4(RC IN (CANTCO, CANTPRO)) FROM Asset THEN {
                                                            CALL Atomic_Alert_Operator(Recipient=Operator_A, Message="ALERT: Control termination was rejected by the asset (CANTCO/CANTPRO). Manual intervention required.");
                                                            TERMINATE; // 流程异常结束
                                                }
                                                    
                                                // 失败场景 2: 等待超时，未收到任何回执
                                                ON TIMEOUT THEN {
                                                            CALL Atomic_Alert_Operator(Recipient=Operator_A, Message="ALERT: No machine receipt received for termination command. Control status is uncertain.");
                                                            TERMINATE; // 流程异常结束
                                                }
                                    }
                        }
            }

                
            // =================================================================
            // 1. 原子流程 (Atomic Procedures) - 仅保留非消息发送的原子流程
            // =================================================================

            // [REMOVED] Atomic_Send_J12_4
            // [REMOVED] Atomic_Broadcast_J12_4
            // [REMOVED] Atomic_Send_J0_3
	PROCEDURE Atomic_Alert_Operator(Recipient: STRING, Message: STRING) "Alerts a specific human operator with a message." {
    // 更新 PARTICIPANTS 以包含 NOTIFY 动作的发送者 (假定为 Own_Unit)
        STEPS {
            STEP Own_Unit NOTIFY Message TO Recipient;
        }
    }
}