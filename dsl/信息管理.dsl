FUNCTION_MODEL Link16_Difference_Report_Optimized_Commented {

    // =================================================================
    // 1. 声明块 (Declarations Block)
    // 定义模型中使用的所有基本元素，如参与者、消息、数据和状态。
    // =================================================================
    // 类型定义块
    TYPES {
        // 定义通用的上下文数据结构
        ContextData : DICTIONARY;
        // 定义航迹数据结构
        TrackData : STRUCT {
            TN : INTEGER;
            Identity : INTEGER;
            Environment : INTEGER;
            ExerciseIndicator : INTEGER;
            Platform : INTEGER;
            Activity : INTEGER;
            SpecificType : INTEGER;
        };
    }
    
    // 定义模型中的参与者及其类型
    ACTORS {
        My_C2_Unit      : C2_JU;            // 本机，一个指挥控制单元
        Reporting_Unit  : GENERIC_PLATFORM; // 任何报告该航迹的远程单元
        Operator        : NON_IU;           // 本机操作员，作为通告和确认的接收方
        System_Log      : NON_IU;           // 用于内部通知
    }

    // 列出模型中涉及的关键J系列消息
    MESSAGES {
        J2.2;  // PPLI (Precise Participant Location and Identification) 消息
        J3.2;  // 空中航迹监视消息，用于传递航迹数据
        J7.0;  // 航迹管理消息，用于差异报告、放弃航迹等管理功能
        J2.X;  // 为 TRIGGER 添加 J2.X
        J3.X;  // 为 TRIGGER 添加 J3.X
    }

    // 定义消息字段中使用的枚举值，增强可读性
    DISCRETES {
        // 定义身份(ID)的枚举值
        ENUM Identity_Values {
            PENDING        = 0 "Pending";
            UNKNOWN        = 1 "Unknown";
            ASSUMED_FRIEND = 2 "Assumed Friend";
            FRIEND         = 3 "Friend";
            NEUTRAL        = 4 "Neutral";
            SUSPECT        = 5 "Suspect";
            HOSTILE        = 6 "Hostile";
        }
        
        // 定义环境/类别(E/C)的枚举值
        ENUM EC_Values {
            SPACE = 1 "Space";
            AIR   = 2 "Air";
            SURF  = 3 "Surface";
            SUB   = 4 "Subsurface";
            LAND  = 5 "Land";
            LAND_PT = 6 "Land Point";
            EW_FIX = 7 "EW Fix";
            EW_AOP = 8 "EW Area of Probability";
            ASW_RB = 9 "ASW Red/Black";
            ASW_POINTS = 10 "ASW Points";
        }

        // 定义E/C变更后对航迹号(TN)的处理动作
        ENUM TN_Change_Action {
            S              = 0 "Same TN";     // 保留原TN
            N              = 1 "New TN";      // 必须更换TN
            X              = 2 "Illegal";     // 非法变更
            NOT_APPLICABLE = 3 "N/A";       // 不适用
            N_BRACKET_3    = 4 "N(3)";      // 特殊规则 N(3)
            BRACKET_2      = 5 "(2)";       // 特殊规则 (2)
        }

        // 定义ID差异解决的决策动作
        ENUM ID_Resolution_Action {
            NO_ACTION  = 0 "No Action";
            ALERT      = 1 "Alert Operator";
            ACCEPT     = 2 "Auto Accept";
            REJECT     = 3 "Auto Reject";
            ALERT_AUTO = 4 "Alert and optionally Auto Accept (1*)";
        }
    }

    // 定义全局状态变量，全局性的、与具体航迹无关，System_Config_IDI1_Action是适用于所有ID冲突处理的系统配置
    STATES {
        System_Config_IDI1_Action : INTEGER = 1; // IDI=1时的配置: 1=处理, 2=仅提醒
    }

    // 定义数据映射规则表
    MAPPINGS {
        // 形式化表4.7-1: E/C变化与TN保持性规则
        MAP EC_Change_Rules {
            (SPACE, SPACE) -> NOT_APPLICABLE;
            (SPACE, AIR) -> S;
            (SPACE, SURF) -> X;
            (SPACE, SUB) -> X;
            (SPACE, LAND) -> X;
            (SPACE, LAND_PT) -> X;
            (SPACE, EW_FIX) -> N;
            (SPACE, EW_AOP) -> N;
            (SPACE, ASW_RB) -> X;
            (SPACE, ASW_POINTS) -> X;

            (AIR, SPACE) -> S;
            (AIR, AIR) -> NOT_APPLICABLE;
            (AIR, SURF) -> S;
            (AIR, SUB) -> X;
            (AIR, LAND) -> S;
            (AIR, LAND_PT) -> X;
            (AIR, EW_FIX) -> N;
            (AIR, EW_AOP) -> N;
            (AIR, ASW_RB) -> X;
            (AIR, ASW_POINTS) -> X;

            (SURF, SPACE) -> X;
            (SURF, AIR) -> S;
            (SURF, SURF) -> NOT_APPLICABLE;
            (SURF, SUB) -> S;
            (SURF, LAND) -> S;
            (SURF, LAND_PT) -> X;
            (SURF, EW_FIX) -> N;
            (SURF, EW_AOP) -> N;
            (SURF, ASW_RB) -> N;
            (SURF, ASW_POINTS) -> N_BRACKET_3;

            (SUB, SPACE) -> X;
            (SUB, AIR) -> X;
            (SUB, SURF) -> S;
            (SUB, SUB) -> NOT_APPLICABLE;
            (SUB, LAND) -> X;
            (SUB, LAND_PT) -> X;
            (SUB, EW_FIX) -> N;
            (SUB, EW_AOP) -> N;
            (SUB, ASW_RB) -> N;
            (SUB, ASW_POINTS) -> N_BRACKET_3;

            (LAND, SPACE) -> X;
            (LAND, AIR) -> S;
            (LAND, SURF) -> S;
            (LAND, SUB) -> X;
            (LAND, LAND) -> NOT_APPLICABLE;
            (LAND, LAND_PT) -> N;
            (LAND, EW_FIX) -> N;
            (LAND, EW_AOP) -> N;
            (LAND, ASW_RB) -> X;
            (LAND, ASW_POINTS) -> X;

            (LAND_PT, SPACE) -> N;
            (LAND_PT, AIR) -> N;
            (LAND_PT, SURF) -> N;
            (LAND_PT, SUB) -> N;
            (LAND_PT, LAND) -> N;
            (LAND_PT, LAND_PT) -> NOT_APPLICABLE;
            (LAND_PT, EW_FIX) -> N;
            (LAND_PT, EW_AOP) -> N;
            (LAND_PT, ASW_RB) -> X;
            (LAND_PT, ASW_POINTS) -> X;

            (EW_FIX, SPACE) -> N;
            (EW_FIX, AIR) -> N;
            (EW_FIX, SURF) -> N;
            (EW_FIX, SUB) -> N;
            (EW_FIX, LAND) -> N;
            (EW_FIX, LAND_PT) -> S;
            (EW_FIX, EW_FIX) -> NOT_APPLICABLE;
            (EW_FIX, EW_AOP) -> BRACKET_2;
            (EW_FIX, ASW_RB) -> X;
            (EW_FIX, ASW_POINTS) -> X;

            (EW_AOP, SPACE) -> S;
            (EW_AOP, AIR) -> S;
            (EW_AOP, SURF) -> S;
            (EW_AOP, SUB) -> S;
            (EW_AOP, LAND) -> S;
            (EW_AOP, LAND_PT) -> S;
            (EW_AOP, EW_FIX) -> S;
            (EW_AOP, EW_AOP) -> NOT_APPLICABLE;
            (EW_AOP, ASW_RB) -> X;
            (EW_AOP, ASW_POINTS) -> X;

            (ASW_RB, SPACE) -> X;
            (ASW_RB, AIR) -> X;
            (ASW_RB, SURF) -> S;
            (ASW_RB, SUB) -> S;
            (ASW_RB, LAND) -> X;
            (ASW_RB, LAND_PT) -> X;
            (ASW_RB, EW_FIX) -> X;
            (ASW_RB, EW_AOP) -> X;
            (ASW_RB, ASW_RB) -> NOT_APPLICABLE;
            (ASW_RB, ASW_POINTS) -> N;

            (ASW_POINTS, SPACE) -> X;
            (ASW_POINTS, AIR) -> X;
            (ASW_POINTS, SURF) -> N_BRACKET_3;
            (ASW_POINTS, SUB) -> N_BRACKET_3;
            (ASW_POINTS, LAND) -> X;
            (ASW_POINTS, LAND_PT) -> X;
            (ASW_POINTS, EW_FIX) -> X;
            (ASW_POINTS, EW_AOP) -> X;
            (ASW_POINTS, ASW_RB) -> N;
            (ASW_POINTS, ASW_POINTS) -> NOT_APPLICABLE;
        }

        // 形式化表4.7-2: ID差异解决规则
        MAP ID_Resolution_Rules {
            (PENDING, PENDING) -> NO_ACTION;
            (PENDING, UNKNOWN) -> ACCEPT;
            (PENDING, ASSUMED_FRIEND) -> ACCEPT;
            (PENDING, FRIEND) -> ACCEPT;
            (PENDING, NEUTRAL) -> ACCEPT;
            (PENDING, SUSPECT) -> ACCEPT;
            (PENDING, HOSTILE) -> ALERT_AUTO;

            (UNKNOWN, PENDING) -> REJECT;
            (UNKNOWN, UNKNOWN) -> NO_ACTION;
            (UNKNOWN, ASSUMED_FRIEND) -> ACCEPT;
            (UNKNOWN, FRIEND) -> ACCEPT;
            (UNKNOWN, NEUTRAL) -> ACCEPT;
            (UNKNOWN, SUSPECT) -> ACCEPT;
            (UNKNOWN, HOSTILE) -> ALERT_AUTO;

            (ASSUMED_FRIEND, PENDING) -> REJECT;
            (ASSUMED_FRIEND, UNKNOWN) -> REJECT;
            (ASSUMED_FRIEND, ASSUMED_FRIEND) -> NO_ACTION;
            (ASSUMED_FRIEND, FRIEND) -> ACCEPT;
            (ASSUMED_FRIEND, NEUTRAL) -> ACCEPT;
            (ASSUMED_FRIEND, SUSPECT) -> ALERT;
            (ASSUMED_FRIEND, HOSTILE) -> ALERT;

            (FRIEND, PENDING) -> REJECT;
            (FRIEND, UNKNOWN) -> REJECT;
            (FRIEND, ASSUMED_FRIEND) -> REJECT;
            (FRIEND, FRIEND) -> NO_ACTION;
            (FRIEND, NEUTRAL) -> ALERT;
            (FRIEND, SUSPECT) -> ALERT;
            (FRIEND, HOSTILE) -> ALERT;

            (NEUTRAL, PENDING) -> REJECT;
            (NEUTRAL, UNKNOWN) -> ALERT;
            (NEUTRAL, ASSUMED_FRIEND) -> ALERT;
            (NEUTRAL, FRIEND) -> ALERT;
            (NEUTRAL, NEUTRAL) -> NO_ACTION;
            (NEUTRAL, SUSPECT) -> ALERT;
            (NEUTRAL, HOSTILE) -> ALERT;

            (SUSPECT, PENDING) -> REJECT;
            (SUSPECT, UNKNOWN) -> REJECT;
            (SUSPECT, ASSUMED_FRIEND) -> ALERT;
            (SUSPECT, FRIEND) -> ALERT;
            (SUSPECT, NEUTRAL) -> ALERT;
            (SUSPECT, SUSPECT) -> NO_ACTION;
            (SUSPECT, HOSTILE) -> ALERT_AUTO;

            (HOSTILE, PENDING) -> REJECT;
            (HOSTILE, UNKNOWN) -> ALERT;
            (HOSTILE, ASSUMED_FRIEND) -> ALERT;
            (HOSTILE, FRIEND) -> ALERT;
            (HOSTILE, NEUTRAL) -> ALERT;
            (HOSTILE, SUSPECT) -> ALERT;
            (HOSTILE, HOSTILE) -> NO_ACTION;
        }
    }

    // =================================================================
    // 2. 流程与规则定义块 (Logic Block)
    // 定义模型的动态行为，描述参与者如何根据收到的消息和内部状态进行交互。F
    // =================================================================

	// -----------------------------------------------------------------
      // 第三层: 核心流程 (Core Procedure)
      // -----------------------------------------------------------------

      PROCEDURE Core_Process_Incoming_Data_Conflict "Process Incoming Data Conflict" {
        TRIGGER MESSAGE_RECEIVED J3.X OR MESSAGE_RECEIVED J7.0 OR MESSAGE_RECEIVED J2.X;
            STEPS {
                  // 优先级 0: 处理PPLI消息带来的特殊更新规则
                  IF Context.Is_From_PPLI_Report == TRUE THEN {
                        CALL Sub_Handle_PPLI_Update();
                        TERMINATE;
                  }

                  ASSIGN Local_Track = GET_LOCAL_TRACK(TN=Context.Current_TN);
                  IF Local_Track == NULL THEN {
                        // [MODIFIED] L3调用L2
                        CALL Sub_Log_To_System(Message="Local track not found for TN. No conflict resolution needed.");
                        TERMINATE;
                  }

                  // **关键逻辑：体现优先级**
                  // 优先级 1: E/C冲突
                  IF Context.Remote_EC != Local_Track.Environment THEN {
                        CALL Sub_Handle_EC_Conflict();
                        TERMINATE;
                  }
                  // 优先级 2: 演习指示器冲突
                  ELSE_IF Context.Remote_Exercise_Indicator != Local_Track.Exercise_Indicator THEN {
                        CALL Sub_Handle_Exercise_Indicator_Conflict();
                  }
                  // 优先级 3: ID冲突
                  ELSE_IF Context.Remote_ID != Local_Track.Identity THEN {
                        CALL Sub_Handle_ID_Conflict();
                  }
                  ELSE {
                TERMINATE;
            }
            }
      }
       
      // -----------------------------------------------------------------
      // 第二层: 子流程 (Sub-procedures)
      // -----------------------------------------------------------------

      // 子流程 1: 处理PPLI带来的ID更新
      PROCEDURE Sub_Handle_PPLI_Update "Handle PPLI Update" {
            STEPS {
                  IF Context.Remote_EC != GET_LOCAL_EC(TN=Context.Current_TN) THEN {
                        CALL Sub_Handle_EC_Conflict(base_rule_override="");
                  }
                  ASSIGN PPLI_ID_Indicator = Context.Remote_Message_Data.PPLI_Identity_Indicator;
                  IF PPLI_ID_Indicator == 1 AND Context.Remote_ID == Identity_Values.FRIEND AND GET_LOCAL_ID(TN=Context.Current_TN) != Identity_Values.HOSTILE THEN {
                        CALL Atomic_Log_To_System(Message="Auto-accepting FRIEND ID based on special PPLI rule.");
                        CALL Atomic_Set_Track_Identity(TN=Context.Current_TN, New_ID=Identity_Values.FRIEND);
                CALL Sub_Update_Associated_Data(TN=Context.Current_TN);
                CALL Sub_Report_Local_ID_Change(TN=Context.Current_TN, New_ID=Identity_Values.FRIEND);
                  }
                  ELSE {
                        CALL Atomic_Log_To_System(Message="PPLI update does not meet auto-accept criteria. Falling back to standard ID conflict resolution.");
                        CALL Sub_Handle_ID_Conflict();
                  }
            }
      }

      // 子流程 2: 专门处理环境/类别(E/C)冲突
      PROCEDURE Sub_Handle_EC_Conflict (base_rule_override: STRING) "Handle E/C Conflict" {
            STEPS {
                  ASSIGN Local_EC = GET_LOCAL_EC(TN=Context.Current_TN);
                  IF base_rule_override == "" THEN {
                ASSIGN base_rule = EC_Change_Rules(Local=Local_EC, Remote=Context.Remote_EC);
            }
            ELSE {
                // 【修改】处理传入的字符串覆盖值，转换为枚举标识符
                IF base_rule_override == "N" THEN {
                    ASSIGN base_rule = TN_Change_Action.N;
                }
                ELSE_IF base_rule_override == "S" THEN {
                    ASSIGN base_rule = TN_Change_Action.S;
                }
                ELSE_IF base_rule_override == "X" THEN {
                    ASSIGN base_rule = TN_Change_Action.X;
                }
                ELSE {
                    STEP "ERROR: Invalid string value received in base_rule_override.";
                    TERMINATE;
                }
            }

                  IF base_rule == TN_Change_Action.S THEN {
                CALL Atomic_Alert_Operator(Recipient=Operator, Message="Track E/C changed. Rule(S): Retaining same TN.");
                CALL Sub_Report_Local_EC_Change(New_EC=Context.Remote_EC); // New_EC 仍是原始值
            }
                  
                  ELSE_IF base_rule == TN_Change_Action.N THEN {
                        CALL Atomic_Alert_Operator(Recipient=Operator, Message="Track E/C changed. Rule(N): New TN required.");
                IF My_C2_Unit.HAS_R2_FOR(TN=Context.Current_TN) == TRUE THEN {
                              CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                                    Sender = My_C2_Unit,
                                    MessageType = "J7.0",
                                    Params = {
                                          ReferenceTN = Context.Current_TN,
                                          ACT = 0 // Drop Track
                                    },
                                    Mode = "BROADCAST",
                                    Recipient = NULL,
                                    ToAddress = NULL
                              );
                              ASSIGN New_TN = GENERATE_NEW_TN; // 假设 New_TN 是局部变量
                    CALL Atomic_Log_To_System(Message="As R2, dropped old TN. System will report with new TN.");
                        }
                        ELSE {
                              CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                                    Sender = My_C2_Unit,
                                    MessageType = "J7.0",
                                    Params = {
                                          ReferenceTN = Context.Current_TN,
                            ACT = 1,
                            Environment = Context.Remote_EC,
                            Identity = GET_LOCAL_ID(TN=Context.Current_TN),
                            ControllingUnitIndicator = My_C2_Unit.IS_CONTROLLING_UNIT_FOR(TN=Context.Current_TN)
                                    },
                                    Mode = "BROADCAST",
                                    Recipient = NULL,
                                    ToAddress = NULL
                              );
                        }
                  }
            ELSE_IF base_rule == TN_Change_Action.N_BRACKET_3 THEN {
                CALL Atomic_Alert_Operator(Recipient=Operator, Message="ASW-related E/C change detected. Rule N(3): Checking point type.");
                IF GET_ASW_POINT_TYPE(Track=GET_LOCAL_TRACK(TN=Context.Current_TN)) IN (1, 2, 4, 5, 12) THEN {
                    CALL Sub_Handle_EC_Conflict(base_rule_override="N");
                }
                ELSE {
                    CALL Sub_Handle_EC_Conflict(base_rule_override="X");
                }
            }
                  ELSE_IF base_rule == TN_Change_Action.BRACKET_2 THEN {
                CALL Atomic_Alert_Operator(Recipient=Operator, Message="EW FIX->AOP change detected. Rule (2): Checking number of fixes.");
                IF GET_NUMBER_OF_FIXES_FOR_AOP(Data=Context.Remote_Message_Data) == 1 THEN {
                    CALL Sub_Handle_EC_Conflict(base_rule_override="S");
                }
                ELSE {
                    CALL Sub_Handle_EC_Conflict(base_rule_override="N");
                }
            }
            ELSE { // TN_Change_Action.X or TN_Change_Action.NOT_APPLICABLE
                CALL Atomic_Alert_Operator(Recipient=Operator, Message="Illegal or Not-Applicable E/C change for TN. Update rejected.");
            }
            }
      }

      // 子流程 2a: 上报本地E/C变更
      PROCEDURE Sub_Report_Local_EC_Change(New_EC: STRING) "Report Local E/C Change" { 
            STEPS {
                  IF My_C2_Unit.HAS_R2_FOR(TN=Context.Current_TN) == TRUE THEN {
                  	ASSIGN Converted_EC = EC_Values.FromString(Value=New_EC); // 假设 EC_Values.FromString 是有效的转换函数调用
                        CALL Atomic_Set_R2_Next_Report_Data(
                    TN=Context.Current_TN,
                    Identity=NULL,
                    Environment=Converted_EC, // 传递转换后的枚举值
                    IdentityDifferenceIndicator=0 // 传递 0 替代 NULL 以匹配 INTEGER
                );
                  }
                  ELSE {
                        CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                              Sender = My_C2_Unit,
                              MessageType = "J7.0",
                              Params = {
                        ReferenceTN = Context.Current_TN,
                        ACT = 1,
                        Environment = New_EC,
                        Identity = GET_LOCAL_ID(TN=Context.Current_TN),
                        ControllingUnitIndicator = My_C2_Unit.IS_CONTROLLING_UNIT_FOR(TN=Context.Current_TN)
                    },
                              Mode = "BROADCAST",
                              Recipient = NULL,
                              ToAddress = NULL
                        );
                  }
            }
      }

      // 子流程 3: 专门处理演习指示器冲突
      PROCEDURE Sub_Handle_Exercise_Indicator_Conflict "Handle Exercise Indicator Conflict" {
        STEPS {
            CALL Atomic_Alert_Operator(Recipient=Operator, Message="Exercise Indicator conflict for TN. Manual resolution required.");
        }
    }

      // 子流程 4: 专门处理身份(ID)冲突
      PROCEDURE Sub_Handle_ID_Conflict "Handle Identity (ID) Conflict" {
            STEPS {
                  // 顶层优先级: 控制单元(CU)对航迹的ID具有最高权威。
                  IF My_C2_Unit.IS_CONTROLLING_UNIT_FOR(TN=Context.Current_TN) == TRUE THEN {
                        CALL Atomic_Alert_Operator(Recipient=Operator, Message="Rejected remote ID as Controlling Unit (CU) and re-asserted local ID.");
                        CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                              Sender = My_C2_Unit,
                              MessageType = "J7.0",
                              Params = {
                        ReferenceTN = Context.Current_TN,
                        ACT = 1,
                        Identity = GET_LOCAL_ID(TN=Context.Current_TN),
                        ControllingUnitIndicator = TRUE
                    },
                              Mode = "BROADCAST",
                              Recipient = NULL,
                              ToAddress = NULL
                        );
                        TERMINATE;
                  }

                  // 根据消息来源和标志位，查询决策表并调用相应解析流程。
                  IF Context.Is_From_J70_Report == TRUE THEN {
                        IF Context.Remote_CUI_Flag == TRUE THEN {
                              CALL Atomic_Alert_Operator(Recipient=Operator, Message="Auto-accepting ID update from Controlling Unit (CU).");
                              ASSIGN Converted_ID = Identity_Values.FromValue(Value=Context.Remote_ID); // 假设转换函数
                    CALL Atomic_Set_Track_Identity(TN=Context.Current_TN, New_ID=Converted_ID);
                    CALL Sub_Update_Associated_Data(TN=Context.Current_TN);
                    CALL Sub_Report_Local_ID_Change(TN=Context.Current_TN, New_ID=Converted_ID);
                        }
                        ELSE {
                              ASSIGN id_action = ID_Resolution_Rules(Local=GET_LOCAL_ID(TN=Context.Current_TN), Value=Context.Remote_ID);
                              CALL Sub_Resolve_ID_Action_By_Role(action=id_action);
                        }
                  }
                  ELSE_IF Context.Is_From_J3X_Report == TRUE THEN {
                        IF Context.Remote_IDI_Flag == FALSE THEN {
                              ASSIGN id_action = ID_Resolution_Rules(Local=GET_LOCAL_ID(TN=Context.Current_TN), Value=Context.Remote_ID);
                              CALL Sub_Resolve_ID_Action_By_Role(action=id_action);
                        }
                        ELSE { // Remote_IDI_Flag == TRUE
                              IF System_Config_IDI1_Action == 1 THEN { // Process IDI=1
                                    ASSIGN id_action = ID_Resolution_Rules(Local=GET_LOCAL_ID(TN=Context.Current_TN), Value=Context.Remote_ID);
                                    CALL Sub_Resolve_ID_Action_By_Role(action=id_action);
                              }
                              ELSE { // Configured to ignore/only alert on IDI=1
                                    CALL Atomic_Alert_Operator(Message="IDI=1, configured to take no action. Operator attention advised.");
                              }
                        }
                  }
            }
      }

      // 子流程 4a: 根据决策动作和本机角色解析ID
      PROCEDURE Sub_Resolve_ID_Action_By_Role(action: INTEGER) "Resolve ID Action Based on Unit Role" {
            STEPS {
                  IF My_C2_Unit.HAS_R2_FOR(TN=Context.Current_TN) == TRUE THEN {
                        // R2 Unit Logic
                        IF action == ID_Resolution_Action.ACCEPT OR action == ID_Resolution_Action.ALERT_AUTO THEN {
                              ASSIGN Converted_ID = Identity_Values.FromValue(Value=Context.Remote_ID); // 假设转换函数
                              CALL Atomic_Set_Track_Identity(TN=Context.Current_TN, New_ID=Converted_ID);
                              CALL Sub_Update_Associated_Data(TN=Context.Current_TN);
                              CALL Sub_Report_Local_ID_Change(TN=Context.Current_TN, New_ID=Converted_ID);
                              CALL Atomic_Log_To_System(Message="As R2, auto-accepted ID based on resolution rules.");
                        }
                        ELSE_IF action == ID_Resolution_Action.REJECT THEN {
                              CALL Atomic_Log_To_System(Message="As R2, auto-rejected ID. Will continue reporting local ID.");
                        }
                        ELSE { // ALERT
                              CALL Atomic_Alert_Operator(Message="ID conflict. As R2, will report local ID with conflict indicator.");
                              CALL Atomic_Set_R2_Next_Report_Data(TN=Context.Current_TN, Identity=NULL, Environment=NULL, IdentityDifferenceIndicator=1);
                        }
                  }
                  ELSE { // Non-R2 Unit Logic
                        IF action == ID_Resolution_Action.ACCEPT OR action == ID_Resolution_Action.ALERT_AUTO THEN {
                              ASSIGN Converted_ID = Identity_Values.FromValue(Value=Context.Remote_ID); // 假设转换函数
                              CALL Atomic_Set_Track_Identity(TN=Context.Current_TN, New_ID=Converted_ID);
                              CALL Sub_Update_Associated_Data(TN=Context.Current_TN);
                              CALL Sub_Report_Local_ID_Change(TN=Context.Current_TN, New_ID=Converted_ID);
                              CALL Atomic_Alert_Operator(Message="Auto-accepted remote ID based on resolution rules.");
                        }
                        ELSE_IF action == ID_Resolution_Action.REJECT THEN {
                              CALL Atomic_Alert_Operator(Message="Auto-rejected remote ID. Reporting local ID via J7.0.");
                              CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                                    Sender = My_C2_Unit,
                                    MessageType = "J7.0",
                                    Params = {
                            ReferenceTN = Context.Current_TN,
                            ACT = 1,
                            Identity = GET_LOCAL_ID(TN=Context.Current_TN),
                            Environment = GET_LOCAL_EC(TN=Context.Current_TN),
                            ControllingUnitIndicator = My_C2_Unit.IS_CONTROLLING_UNIT_FOR(TN=Context.Current_TN)
                        },
                                    Mode = "BROADCAST",
                                    Recipient = NULL,
                                    ToAddress = NULL
                              );
                        }
                        ELSE { // ALERT
                              CALL Atomic_Alert_Operator(Message="ID conflict detected. Suspending difference reports for this track.");
                        }
                  }
            }
      }

      // 子流程 4b: 处理ID变更时的关联数据更新
      PROCEDURE Sub_Update_Associated_Data(TN: INTEGER) "Update Associated Data After ID Change" {
            STEPS {
                  CALL Atomic_Log_To_System(Message="Identity has changed for TN " + TN + ". Evaluating associated data.");
                  ASSIGN Remote_Platform = Context.Remote_Message_Data.Platform;
                  ASSIGN Local_Platform = GET_LOCAL_PLATFORM(ReferenceTN=TN);
                  IF Remote_Platform == "No_Statement" AND Local_Platform != "No_Statement" THEN {
                        CALL Atomic_Log_To_System(Message="Remote platform is 'No Statement', retaining local platform data for TN " + TN + ".");
                  }
                  ELSE_IF Local_Platform IN ("Tanker", "Tanker_Boom") AND NOT (Remote_Platform IN ("Tanker", "Tanker_Boom")) THEN {
                        CALL Atomic_Alert_Operator(Message="Warning: Tanker platform information for TN " + TN + " has changed.");
                        CALL Atomic_Update_Track_Associated_Data(ReferenceTN=TN);
                        CALL Atomic_Log_To_System(Message="Associated data updated for TN " + TN + " after tanker info change.");
                  }
                  ELSE {
                        CALL Atomic_Update_Track_Associated_Data(ReferenceTN=TN);
                        CALL Atomic_Log_To_System(Message="Associated platform/activity data synchronized for TN " + TN + ".");
                  }
            }
      }

      // 子流程 4c: 专门处理本地ID变更的上报
      PROCEDURE Sub_Report_Local_ID_Change(TN: INTEGER, New_ID: INTEGER) "Report Local ID Change" {
            STEPS {
                  IF My_C2_Unit.HAS_R2_FOR(ReferenceTN=TN) == TRUE THEN {
                        CALL Atomic_Set_R2_Next_Report_Data(ReferenceTN=TN, Identity=New_ID, Environment=NULL, IdentityDifferenceIndicator=0);
                  }
                  ELSE {
                        ASSIGN is_cu = My_C2_Unit.IS_CONTROLLING_UNIT_FOR(ReferenceTN=TN);
                        CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                              Sender = My_C2_Unit,
                              MessageType = "J7.0",
                              Params = {
                        ReferenceTN = TN,
                        ACT = 1,
                        Identity = New_ID,
                        ControllingUnitIndicator = is_cu
                    },
                              Mode = "BROADCAST",
                              Recipient = NULL,
                              ToAddress = NULL
                        );
                  }
            }
      }

    // [NEW] 子流程: 向系统日志记录 (L2封装L1)
    // 描述: 封装了 "Atomic_Log_To_System" 的L1原子流程，以满足L3->L2的调用规则。
    PROCEDURE Sub_Log_To_System (Message: STRING) "Log message to system" {
        STEPS {
            // L2 调用 L1
            CALL Atomic_Log_To_System(Message=Message);
        }
    }


      // -----------------------------------------------------------------
      // 第一层: 原子流程 (Atomic Procedures)
      // -----------------------------------------------------------------

      // 原子流程: 向操作员发送一条告警。
      PROCEDURE Atomic_Alert_Operator(Recipient: STRING, Message: STRING) "Alert Operator" {
        STEPS {
            STEP My_C2_Unit NOTIFY Message TO Recipient; // 使用传入的 Recipient
        }
    }

      // 原子流程: 向系统日志记录一条内部通知。
      PROCEDURE Atomic_Log_To_System(Message: STRING) "Log to System" {
        STEPS {
            STEP My_C2_Unit NOTIFY Message TO System_Log;
        }
    }

      // [REMOVED] Atomic_Broadcast_J70_Difference_Report
      // [REMOVED] Atomic_Broadcast_J70_Drop_Track

      // 原子流程: 直接更新本地航迹数据库中的身份字段。
      PROCEDURE Atomic_Set_Track_Identity(TN: INTEGER, New_ID: INTEGER) "Set Track's Identity Field" {
        STEPS {
            ASSIGN GET_LOCAL_TRACK(ReferenceTN=TN).Identity = New_ID; // 假设赋值支持字符串
        }
    }

      // 原子流程: 更新本地航迹数据库中的关联数据。
      PROCEDURE Atomic_Update_Track_Associated_Data(TN: INTEGER) "Update Track's Associated Data" {
        STEPS {
            ASSIGN GET_LOCAL_TRACK(ReferenceTN=TN).Platform = Context.Remote_Message_Data.Platform;
            ASSIGN GET_LOCAL_TRACK(ReferenceTN=TN).Activity = Context.Remote_Message_Data.Activity;
        }
    }

      // 原子流程: 为R2单元设置下一次监视报告中要包含的数据。
      PROCEDURE Atomic_Set_R2_Next_Report_Data(TN: INTEGER, Identity: INTEGER, Environment: INTEGER, IdentityDifferenceIndicator: INTEGER) "Set Data for Next R2 Surveillance Report" {
        STEPS {
            STEP NATURAL_LANGUAGE {
                INTENT "Queue data update for next R2 report";
                DESCRIPTION "This unit, as R2 for the track, will include the specified updated data (Identity, E/C, and/or IDI flag) in its next J3.X surveillance transmission for that TN.";
            };
        }
    }
}