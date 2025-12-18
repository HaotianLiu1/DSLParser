FUNCTION_MODEL Track_Correlation_And_Decorrelation {
    // 模块描述: 本模型详细定义了 MIL-STD-6016B 4.4.4.3 章节中描述的空中与海面航迹的相关与解相关功能。
    // 它包含了从触发、测试、决策到执行的完整流程，并遵循了三层建模思想。

    // 1. 参与者定义
    ACTORS {
        Own_Unit: C2_JU;       // 本指挥控制单元
        Remote_Unit: C2_JU;    // 远程指挥控制单元
        Operator: NON_IU;      // 本单元操作员
    }

    // 2. 消息定义
    MESSAGES {
        J2.0; J2.2; J2.3;      // PPLI 消息
        J3.2; J3.3;            // 航迹消息
        J7.0;                  // 航迹管理消息 (丢弃航迹/身份差异)
        J7.2;                  // 相关消息
        J7.4;                  // 备用航迹号消息
        J9.0;                  // 指令消息
        J10.2;                 // 交战状态消息
        J10.3;                 // 移交消息
        J10.5;                 // 控制单元报告消息
        J10.6;                 // 配对消息
        J12.0;                 // 任务分配消息
        J12.5;                 // 索引号关联消息
        J12.6;                 // 目标分类消息
    }

    // 3. 状态定义
    STATES {
        TentativeCorrelationFlag: BOOLEAN = FALSE; // 临时相关标志
        DroppedTN_AwaitingAck: BOOLEAN = FALSE;    // 丢弃航迹等待 J7.0 确认标志
        CorrelationRetryLockout: BOOLEAN = FALSE;  // 60秒关联重试锁定标志
        DecorrelationPendingFlag: BOOLEAN = FALSE; // 待解相关标志 (用于移交等情况)
        CorrelationExecuted: BOOLEAN = FALSE;      // 标记关联是否已成功执行并合并了航迹
        DroppedTN: INTEGER = 0;                 // 用于存储 Sub_SelectDroppedTN 的结果
        RetainedTN: INTEGER = 0;                // 用于存储 Sub_SelectDroppedTN 的结果
        PhysicalTestPassed: BOOLEAN = FALSE;    // 用于存储 Atomic_PerformPhysicalCorrelationTests 的结果
      
        Generated_New_TN: INTEGER = 0;  // 用于解决 "ASSIGN = CALL" 问题
        MatchedRemoteTN: INTEGER = 0;   // 已匹配的远程航迹号,用于解决 "ON ... 未定义变量" 问题
        TentativeTrackTN: INTEGER = 0;  // 正在尝试相关的目标航迹号,用于解决 "ON ... 未定义变量" 问题
        HasProhibitions: BOOLEAN = FALSE;  // 新增状态变量，用于存储原子流程的检查结果 (解决 IF Call() 问题)
        HasRestrictions: BOOLEAN = FALSE;  // 新增状态变量，用于存储原子流程的检查结果 (解决 IF Call() 问题)
    }   

    // =================================================================
    // C. 核心流程 (Core Procedures)
    // 描述: 作为顶层入口，管理所有航迹相关与解相关活动，仅包含高级别的逻辑判断与调度。
    // =================================================================
    
    // 核心流程: 航迹相关
    PROCEDURE Core_TrackCorrelation "The top-level process for handling all track correlation activities." {
		TRIGGER MESSAGE_RECEIVED J3.2 FROM Remote_Unit     // 自动触发情况1: 接收远程数据
                                            OR MESSAGE_RECEIVED J3.3 FROM Remote_Unit
                                            OR MESSAGE_RECEIVED J2.X FROM Remote_Unit
                                            OR "Own_Unit prepares to transmit local track"     // 自动触发情况2: 发送本地数据前
                                            OR "Operator requests manual correlation";     // 手动触发
                 
        STEPS {
            // 场景 1: 手动触发
            IF "Trigger is Operator manual request" THEN {
                CALL Sub_Handle_Manual_Correlation();
            }
            // 场景 2: 自动触发 - 因接收到远程数据
            ELSE_IF "Trigger is RECEIVES J3.2" OR "Trigger is RECEIVES J3.3" OR "Trigger is RECEIVES J2.X" THEN {
                // 对于接收场景，唯一的任务就是执行相关性检查与处理。
                CALL Sub_Manage_Automatic_Correlation_Process();
            }
			// 场景 3: 自动触发 - 因准备发送本地航迹
                              ELSE_IF "Trigger is Own_Unit prepares to transmit local track" THEN {
                                        // 首先，执行标准的自动相关管理流程。
                                        CALL Sub_Manage_Automatic_Correlation_Process();
                                           
                                        // 然后，根据相关流程的结果，决定是否继续发送。
                                        IF CorrelationExecuted == FALSE THEN {
                                                  // 如果没有发生航迹合并（重复），则安全地发送本地航迹。
                                                  // [MODIFIED] 调用武器协同的通用发送子流程 (L3调用L2工具)
                                                  CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                                                            Sender = Own_Unit,
                                                            MessageType = "J3.X", // 假设是合适的J3.X类型
                                                            // [FORMATTED] 假设LocalTrackData是包含J3.X字段的字典
                                                            Params = {
                                                                      // 示例: TrackNumber: LocalTN, Position: ..., Velocity: ...
                                                                      TrackData = LocalTrackData // 使用占位符，需替换为实际J3.X字段
                                                            },
                                                            Mode = "BROADCAST",
                                                            Recipient = NULL,
                                                            ToAddress = NULL
                                                  );
                                        }
                ELSE {
                    // 如果航迹已被合并，则终止发送动作。
                    TERMINATE;
                }
            }
        }
    } 

    // 核心流程: 航迹解相关
    // 描述: 根据触发事件（自动或手动），调度相应的子流程来处理航迹解相关任务。
    PROCEDURE Core_TrackDecorrelation "The top-level process for handling all track decorrelation activities." {
		TRIGGER MESSAGE_RECEIVED J2.X(IsCommonLocalTrack == TRUE) FROM Remote_Unit
                                            OR MESSAGE_RECEIVED J3.X(IsCommonLocalTrack == TRUE) FROM Remote_Unit
                                            OR "Operator requests manual decorrelation";

        STEPS {
            IF "Trigger is Operator manual request" THEN {
                // 手动解相关路径
                CALL Sub_ExecuteDecorrelation();
            }
            ELSE {
                // 自动解相关路径，检查是否满足条件
                IF IsRemoteTrackOutsideDecorrelationWindow == TRUE THEN {
                    CALL Sub_ExecuteDecorrelation();
                }
                ELSE {
                    TERMINATE;
                }
            }
        }
    }


    // =================================================================
    // B. 子流程 (Sub-procedures)
    // 描述: 封装具有特定业务目标的、可复用的逻辑片段，包含详细的步骤、时序和状态控制。
    // =================================================================

    // 子流程: 管理自动相关流程
    PROCEDURE Sub_Manage_Automatic_Correlation_Process "Manages the entire two-step automatic correlation process." {
        STEPS {
            // 执行首次相关性测试。
            CALL Sub_PerformCorrelationTest(AttemptType="First Attempt");

            // 检查首次测试是否成功建立了“临时相关”。
            IF TentativeCorrelationFlag == TRUE THEN {
                // 如果建立了临时相关，则等待下一次“相关激励”事件的发生。
                WAIT {
                    // 根据 MIL-STD-6016B 4.4.4.3.1c(a)，任何相关的远程消息更新都可以触发第二次测试。
                    ON MESSAGE_RECEIVED J3.2(TrackNumber == MatchedRemoteTN) FROM Remote_Unit
                                                           OR MESSAGE_RECEIVED J3.3(TrackNumber == MatchedRemoteTN) FROM Remote_Unit
                                                           OR MESSAGE_RECEIVED J2.2(TrackNumber == TentativeTrackTN) FROM Remote_Unit
                                                           OR MESSAGE_RECEIVED J2.3(TrackNumber == TentativeTrackTN) FROM Remote_Unit
                                                           OR MESSAGE_RECEIVED J2.0(TrackNumber == TentativeTrackTN) FROM Remote_Unit
                                                  THEN {
                        // 执行第二次相关性测试。
                        CALL Sub_PerformCorrelationTest(AttemptType="Second Attempt");
                        // 检查第二次测试是否仍然通过。
                        IF TentativeCorrelationFlag == TRUE THEN {
                            // 如果两次测试均通过，则执行最终的关联操作。
                            CALL Sub_ExecuteFinalCorrelation();
                        }
                        ELSE {
                            // 如果第二次测试失败，则清除临时相关标志并通知操作员。
                            ASSIGN TentativeCorrelationFlag = FALSE;
                            STEP Own_Unit NOTIFY "Tentative correlation failed on second attempt." TO Operator;
                        }
                    }

                    // 根据 MIL-STD-6016B 4.4.4.3.1c(b)，在本单元准备发送本地航迹更新前，也需要触发测试。
                    ON "Own_Unit prepares to transmit local track update for TentativeTrack" THEN {
                        CALL Sub_PerformCorrelationTest(AttemptType="Second Attempt");
                        IF TentativeCorrelationFlag == TRUE THEN {
                            CALL Sub_ExecuteFinalCorrelation();
                        }
                        ELSE {
                            ASSIGN TentativeCorrelationFlag = FALSE;
                            STEP Own_Unit NOTIFY "Tentative correlation failed on second attempt." TO Operator;
                        }
                    }
                }
            }
        }
    }
  
    // 子流程: 处理手动相关
    // 描述: 先进行不可逾越规则的检查，然后直接执行关联。
    PROCEDURE Sub_Handle_Manual_Correlation "Handles the process for manually initiated correlation." {
        STEPS {
            // 检查手动相关是否存在绝对禁止项。
            IF (Track1.E_C != Track2.E_C) OR (Track1.Simulated != Track2.Simulated) OR (Track1.IsRemote == TRUE AND Track2.IsRemote == TRUE) THEN {
                CALL Atomic_Notify_Correlation_Prohibited(Reason="Manual correlation prohibition violation.");
                TERMINATE;
            }
            
            // 如果没有禁止项，则直接调用最终关联流程，跳过两次自动测试。
            CALL Sub_ExecuteFinalCorrelation();
        }
    }
    
    // 子流程: 执行相关性测试
    // 描述: 封装单次的相关性测试逻辑，包括前置检查（禁止项和限制项）和物理参数比对。
    PROCEDURE Sub_PerformCorrelationTest(AttemptType: STRING) "Performs a single round of correlation testing." {
        STEPS {
            // 检查是否存在绝对禁止相关的情况 (Prohibitions)。
            CALL Atomic_CheckCorrelationProhibitions();
            IF HasProhibitions == TRUE THEN {
                TERMINATE;
            }

            // 检查是否存在需要注意的限制条件 (Restrictions)。
            CALL Atomic_CheckCorrelationRestrictions();
            IF HasRestrictions == TRUE THEN{
                // 在应用标准限制前，优先检查是否满足交战例外规则。
                IF (Context.Track_A.IsTargetInOwnUnitJ102 == TRUE AND Context.Track_A.ID IN ("Unknown", "Hostile") AND Context.Track_B.ID == "Friend") OR
                   (Context.Track_B.IsTargetInOwnUnitJ102 == TRUE AND Context.Track_B.ID IN ("Unknown", "Hostile") AND Context.Track_A.ID == "Friend") THEN {
                    // 若满足例外条件，则自动绕过限制，直接进行物理测试。
                    STEP Own_Unit NOTIFY "INFO: Engagement exception rule applied. Overriding correlation restriction." TO Operator;
                    CALL Atomic_PerformPhysicalCorrelationTests();
                }
                ELSE {
                    // 若不满足例外条件，则执行标准的限制处理流程，通知操作员。
                    STEP Own_Unit NOTIFY "Automatic correlation restricted. Please review." TO Operator;
                    // 等待操作员确认是否要覆盖限制。
                    USER_CONFIRM "Operator confirms to override restriction" THEN {
                        // 若操作员同意，则继续物理测试。
                        CALL Atomic_PerformPhysicalCorrelationTests();
                    }
                    ELSE {
                        // 若操作员不同意，则终止流程。
                        TERMINATE;
                    }
                }
            }
            ELSE {
                //如果不存在任何限制项，直接进行物理测试。
                CALL Atomic_PerformPhysicalCorrelationTests();
            }

            // 根据物理测试的结果，更新“临时相关”状态标志。
            IF PhysicalTestPassed == TRUE THEN {
                // 如果测试通过且是首次尝试，则设置临时相关标志。
                IF AttemptType == "First Attempt" THEN {
                    ASSIGN TentativeCorrelationFlag = TRUE;
                }
            }
            ELSE {
                 // 如果测试失败，则清除临时相关标志。
                 ASSIGN TentativeCorrelationFlag = FALSE;
            }
        }
    }

    // 子流程: 执行最终关联
    // 描述: 在确认关联后，根据本单元是否对“待丢弃航迹”拥有报告责任（R²），执行正确的丢弃流程（直接发送 J7.0）或关联请求流程（发送 J7.2），并处理所有中间状态和超时情况。
    PROCEDURE Sub_ExecuteFinalCorrelation "Selects dropped TN, and executes the correct drop or correlation request procedure." {
        STEPS {
            // 根据标准规则（交战例外、OCC约束、TN号大小）确定哪个航迹应该被丢弃。
            CALL Sub_SelectDroppedTN();

            // 检查本单元是否对该待丢弃航迹拥有报告责任(R²)
            IF Own_Unit.HasR2ForDroppedTN == TRUE THEN {
                // 本单元拥有 R²，发送 J7.0 丢弃航迹消息，通知网络该航迹号作废
				CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                                                  Sender = Own_Unit,
                                                  MessageType = "J7.0",
                                                  Params = {
                                                            ReferenceTN = DroppedTN,
                                                            ACT = 0 // Drop Track
                                                  },
                                                  Mode = "BROADCAST", // J7.0 ACT=0 通常是广播
                                                  Recipient = NULL,
                                                  ToAddress = NULL
                                        );
                ASSIGN DroppedTN_AwaitingAck = TRUE;

                // 启动一个60秒的计时器，以监控网络对丢弃消息的反应。
                WAIT FOR 60 SECONDS {
                    // 正常情况: 如果网络确认了丢弃动作，则可以安全地进行数据迁移。
                    ON "Acknowledgement for J7.0 received" THEN {
                        // 完成数据迁移，并将全局标志位设置为 TRUE，表示关联成功。
                        CALL Sub_MigrateDataFromDroppedTN();
                        ASSIGN CorrelationExecuted = TRUE;
                    }

                    // 特殊情况: 在等待期间，如果另一个单元重新报告了刚刚被丢弃的航迹号。
                   ON MESSAGE_RECEIVED J3.X(TrackNumber == DroppedTN) FROM Remote_Unit THEN {
                        // 根据标准，本单元应将其保留为一个新的远程航迹。
                        CALL Atomic_EstablishOriginalTNAsRemote();
                        // 同时，启动一个60秒的锁定计时器，在此期间不得重新尝试关联，以避免循环关联。
                        Own_Unit START_TIMER CorrelationLockoutTimer FOR 60 SECONDS;
                        ASSIGN CorrelationRetryLockout = TRUE;
                        // 即使航迹被重报，原有的数据迁移也应完成。
                        CALL Sub_MigrateDataFromDroppedTN();
                        ASSIGN CorrelationExecuted = TRUE;
                    }
                    
                    // 失败情况: 如果60秒后仍未收到确认，则认为关联失败。
                    ON TIMEOUT THEN {
                        // 通知操作员关联失败，并终止流程。
                        STEP Own_Unit NOTIFY "Correlation failed: No confirmation for J7.0 Drop Track received within 60s." TO Operator;
                        TERMINATE;
                    }
                }
            }
            ELSE {
                // 场景 B: 本单元不拥有 R²，因此无权丢弃该航迹，只能发起“关联请求”。
                // 发起一条 J7.2 相关消息，向网络声明这次关联，并间接请求拥有 R² 的单元来执行丢弃动作。
                CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                                                  Sender = Own_Unit,
                                                  MessageType = "J7.2",
                                                  Params = {
                                                            DroppedTN_Field = DroppedTN,     // 示例字段名，需替换
                                                            RetainedTN_Field = RetainedTN    // 示例字段名，需替换
                                                  },
                                                  Mode = "SEND", // 按原DSL意图设为 SEND
                                                  Recipient = Remote_Unit,
                                                  ToAddress = NULL
                                        );

                // 在等待丢弃确认期间，必须将该待丢弃航迹号作为远程航迹临时保留。
                STEP NATURAL_LANGUAGE {
                    INTENT "Retain Dropped TN as a remote track after initiating J7.2.";
                    DESCRIPTION "In accordance with MIL-STD-6016B 4.4.4.3.1k(1)(c), the Dropped TN shall be retained as a remote track while awaiting the drop confirmation from the responsible unit.";
                };
                
                // 启动一个60秒的计时器，等待拥有 R² 的单元发送 J7.0 消息作为响应。
                WAIT FOR 60 SECONDS {
                    // 成功情况: 在超时前，成功收到了来自网络（通常是拥有 R² 的单元）的 J7.0 丢弃消息。
                    ON MESSAGE_RECEIVED J7.0(ACT==0 AND TrackNumber == DroppedTN) FROM Remote_Unit THEN {
                        // 收到确认后，执行数据迁移，并标记关联成功。
                        CALL Sub_MigrateDataFromDroppedTN();
                        ASSIGN CorrelationExecuted = TRUE;
                    }

                    // 失败情况: 如果60秒后仍未收到预期的 J7.0 消息，则认为关联失败。
                    ON TIMEOUT THEN {
                        // 通知操作员关联失败，并终止流程。
                        STEP Own_Unit NOTIFY "Correlation failed: Did not receive J7.0 for dropped TN within 60s." TO Operator;
                        TERMINATE;
                    }
                }
            }
        }
    }

    // 子流程: 选择待丢弃航迹
    PROCEDURE Sub_SelectDroppedTN "Selects the track number to be dropped based on standard rules." {
        STEPS {
            // 优先级 0: 首先处理“交战例外”的强制规定。
            IF (Context.IsEngagementExceptionActive == TRUE) THEN {
                // 如果是，则必须选择“未知/敌机”身份的航迹作为待丢弃航迹，流程结束。
                STEP NATURAL_LANGUAGE {
                    INTENT "Force select the Unknown/Hostile track to be dropped.";
                    DESCRIPTION "In accordance with the engagement exception rule, the track with the ID of Unknown or Hostile shall be selected as the Dropped TN.";
                };
            }
            ELSE {
                // 如果不是例外情况，则执行标准的选择逻辑。
                // 优先级 1: 约束优先原则。
                // 情况 A: 航迹A有约束，航迹B没有 -> 必须丢弃航迹B。
                IF TrackA.HasOCC == TRUE AND TrackB.HasOCC == FALSE THEN {
                    STEP NATURAL_LANGUAGE {
                        INTENT "Assign Track B as the Dropped TN.";
                        DESCRIPTION "Track B is selected to be dropped as it does not have an Operational Contingency Constraint, while Track A does.";
                    };
                }
                // 情况 B: 航迹B有约束，航迹A没有 -> 必须丢弃航迹A。
                ELSE_IF TrackA.HasOCC == FALSE AND TrackB.HasOCC == TRUE THEN {
                    STEP NATURAL_LANGUAGE {
                        INTENT "Assign Track A as the Dropped TN.";
                        DESCRIPTION "Track A is selected to be dropped as it does not have an Operational Contingency Constraint, while Track B does.";
                    };
                }
                // 优先级 2: 自动选择规则（当约束相同时）。
                ELSE {
                    // 确定用于比较的有效航迹号，处理J7.4特殊情况。
                    STEP NATURAL_LANGUAGE {
                        INTENT "Determine effective track numbers for comparison.";
                        DESCRIPTION "The effective track number for each track will be determined, using the value greater than 07777 if it is reported via a J7.4 message.";
                    };
                    
                    // 比较有效航迹号，选择较大的一个作为待丢弃航迹。
                    IF Get_Effective_TN(Track=TrackA) > Get_Effective_TN(Track=TrackB) THEN {
                         STEP NATURAL_LANGUAGE {
                            INTENT "Assign Track A as the Dropped TN.";
                            DESCRIPTION "Track A is selected to be dropped as its effective track number is higher.";
                        };
                    }
                    ELSE {
                         STEP NATURAL_LANGUAGE {
                            INTENT "Assign Track B as the Dropped TN.";
                            DESCRIPTION "Track B is selected to be dropped as its effective track number is higher or equal.";
                        };
                    }
                }
            }
        }
    }
   
    
    // 子流程: 从被丢弃航迹迁移数据
    // 描述: 将待丢弃航迹的关键数据（运动学、识别、IFF等）转移至保留航迹。
    PROCEDURE Sub_MigrateDataFromDroppedTN "Transfers specified data from the dropped TN to the retained TN." {
        STEPS {
            // 并行执行所有类型数据的迁移。
            PARALLEL {
                // 迁移运动学数据。
                BRANCH {
                    CALL Atomic_TransferKinematicData();
                }
                // 迁移识别数据。
                BRANCH {
                    CALL Atomic_TransferIdentificationData();
                }
                // 迁移 IFF/SIF 数据。
                BRANCH {
                    CALL Atomic_TransferIFF_SIF_Data();
                }
                // 迁移指示符数据。
                BRANCH {
                    CALL Atomic_TransferIndicatorData();
                }
            }
            // 通知操作员关联成功且数据迁移完成。
            STEP Own_Unit NOTIFY "Correlation successful. Data migration complete." TO Operator;
        }
    }


    // 子流程: 执行解相关
    PROCEDURE Sub_ExecuteDecorrelation "Executes the decorrelation by splitting tracks and handling special conditions." {
        STEPS {
            // 在正式拆分前，将本地航迹与网络上其他所有远程航迹尝试进行一次相关测试。
            CALL Sub_PerformCorrelationTest(AttemptType="Single Attempt");

            // 检查上述测试是否找到了新的关联对象。
            IF TentativeCorrelationFlag == FALSE THEN {
                // 如果没有找到新的关联，说明该本地航迹是独立的，为其分配新TN并报告。
                CALL Atomic_AssignNewTN();
                ASSIGN NewTN = Generated_New_TN;
                                        // [MODIFIED] 调用通用发送子流程报告新TN
                                        CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                                                  Sender = Own_Unit,
                                                  MessageType = "J3.X", // 假设是合适的J3.X类型
                                                  Params = {
                                                            TrackNumber = NewTN, // 使用新分配的TN
                                                            Identity = PENDING   // 初始ID设为Pending
                                                            // ... 可能需要根据上下文填充其他 J3.X 字段
                                                  },
                                                  Mode = "BROADCAST",
                                                  Recipient = NULL,
                                                  ToAddress = NULL
                                        );
                // 将原有的航迹号(TN A)确立为一个独立的远程航迹。
                CALL Atomic_EstablishOriginalTNAsRemote();
                // 检查并处理所有与解相关相关的特殊操作情况（如交战、控制等）。
                CALL Sub_HandleDecorrelationSpecialConditions();
            }
            ELSE {
                // 如果找到了新的关联对象，则中止解相关，转而执行新的关联流程。
                STEP Own_Unit NOTIFY "Decorrelation aborted. New correlation candidate found." TO Operator;
                // 将原有的航迹号 TN A 确立为一个独立的远程航迹。
                CALL Atomic_EstablishOriginalTNAsRemote();
                CALL Sub_ExecuteFinalCorrelation();
            }
        }
    }

    // 子流程: 处理解相关特殊情况
    PROCEDURE Sub_HandleDecorrelationSpecialConditions "Checks and alerts operator for various operational contingencies during decorrelation." {
        STEPS {
            // 步骤 1: 检查航迹是否正处于本单元发起的交战中。
            IF Track_A.IsInEngagement == TRUE THEN {
                STEP Own_Unit NOTIFY "ALERT: Decorrelated track TN A is in an active engagement. Transmit J10.2 with status 'Engagement Broken' if appropriate." TO Operator;
            }

            // 步骤 2: 检查航迹是否涉及待处理的指令消息。
            IF Track_A.HasPendingCommand == TRUE THEN {
                STEP Own_Unit NOTIFY "INFO: Decorrelated track TN A has a pending J9.0 command. Display new status for both TN A and TN B before replying." TO Operator;
            }

            // 步骤 3: 检查航迹是否正由本单元控制。
            IF Track_A.IsControlledByOwnUnit == TRUE AND Track_A.TargetIsC2_JU == TRUE THEN {
                // 若被控方是 C2 JU，则禁止自动解相关，需要手动确认。
                STEP Own_Unit NOTIFY "MANUAL ACTION REQUIRED: Decorrelation of controlled track TN A requires manual confirmation. Automatic decorrelation inhibited." TO Operator;
                TERMINATE;
            }
            ELSE_IF Track_A.IsControlledByOwnUnit == TRUE AND Track_A.TargetIsC2_JU == FALSE THEN {
                STEP // 若被控方是非 C2 JU，则允许解相关，并继续报告对原航迹的控制。
                Own_Unit NOTIFY "INFO: Decorrelated track TN A (non-C2 JU) control report will be maintained." TO Operator;
            }

            // 步骤 4: 检查航迹是否已被本单元配对。
            IF Track_A.IsPaired == TRUE THEN {
                STEP Own_Unit NOTIFY "ALERT: Decorrelated track TN A is paired. Terminate pairing on TN A and initiate on TN B if appropriate." TO Operator;
            }

            // 步骤 5: 检查航迹是否已关联索引号。
            IF Track_A.HasIndexNumber == TRUE THEN {
                STEP NATURAL_LANGUAGE {
                    INTENT "Assess and re-assign Index Number.";
                    ACTORS Own_Unit, Operator;
                    DATA_CONTEXT "J12.5 message associated with TN A.";
                    DESCRIPTION "Assess whether the Index Number should remain with TN A or be transferred to TN B, and transmit J12.5 messages as appropriate.";
                };
            }

            // 步骤 6: 检查航迹是否正处于移交过程中。
            IF Track_A.IsInHandover == TRUE THEN {
                // 若正在移交，则设置“待解相关”标志，并暂停执行。
                ASSIGN DecorrelationPendingFlag = TRUE;
                STEP Own_Unit NOTIFY "INFO: Decorrelation is delayed until handover of TN A is complete or terminated. Status is 'Pending Decorrelation'." TO Operator;
                // 等待移交完成或终止的事件。
                WAIT {
                    ON "Handover of TN A complete or terminated" THEN {
                        // 移交结束后，清除标志并提示操作员。
                        ASSIGN DecorrelationPendingFlag = FALSE;
                        STEP Own_Unit NOTIFY "ALERT: Handover for TN A is finished. Proceeding with pending decorrelation." TO Operator;
                    }
                }
            }
        }
    }


    // =================================================================
    // A. 原子流程 (Atomic Procedures)
    // =================================================================
    
    PROCEDURE Atomic_Notify_Correlation_Prohibited(Reason: STRING) "Notifies the operator that a correlation action was prohibited." {
        STEPS {
            STEP Own_Unit NOTIFY "Correlation is prohibited for the selected tracks." TO Operator;
        }
    }

    PROCEDURE Atomic_CheckCorrelationProhibitions "Checks absolute prohibitions for automatic correlation." {
        STEPS {
            STEP NATURAL_LANGUAGE {
                INTENT "Check for conditions that absolutely forbid correlation.";
                DESCRIPTION "Verify that tracks do not have TQ <= e, are not of different E/C, and are not a mix of simulated and live tracks. The global state 'HasProhibitions' is updated to true if any prohibition is found, otherwise false.";
            };
        }
    }

    PROCEDURE Atomic_CheckCorrelationRestrictions "Checks non-absolute restrictions for automatic correlation." {
        STEPS {
            STEP NATURAL_LANGUAGE {
                INTENT "Check for conditions that restrict automatic correlation.";
                DESCRIPTION "Verify that tracks do not have conflicting IDs, different Mode II codes, are not both local, have strength > 1, have R2 conflicts, or are under Operational Contingency Constraints (OCCs). The global state 'HasRestrictions' is updated to true if any restriction is found, otherwise false.";
            };
        }
    }

    PROCEDURE Atomic_PerformPhysicalCorrelationTests "Performs positional, velocity, and altitude tests." {
        STEPS {
            STEP NATURAL_LANGUAGE {
                INTENT "Execute kinematic and positional tests.";
                DESCRIPTION "Compare the position, velocity, and altitude of the local and remote tracks against the criteria defined in MIL-STD-6016B, paragraphs 4.4.4.3.1f(3) through 4.4.4.3.1f(8).";
            };
        }
    }


    PROCEDURE Atomic_TransferKinematicData "Transfers kinematic data from dropped to retained TN." {
        STEPS {
            STEP "Transfer Latitude, Longitude, Course, Speed, Altitude, TQ, and Strength.";
        }
    }

    PROCEDURE Atomic_TransferIdentificationData "Transfers identification data." {
        STEPS {
            STEP "Transfer ID, Platform, Activity, etc., based on restriction inhibition status.";
        }
    }

    PROCEDURE Atomic_TransferIFF_SIF_Data "Transfers IFF/SIF data." {
        STEPS {
            STEP "Transfer non-zero Mode I/II/III data and higher value Mode IV data.";
        }
    }

    PROCEDURE Atomic_TransferIndicatorData "Transfers Force Tell and Emergency indicators." {
        STEPS {
            STEP "Transfer Force Tell and Emergency indicators if set to 1 on dropped TN.";
        }
    }
          
          PROCEDURE Atomic_AssignNewTN "Assigns a new TN to a local track and returns it." {
        STEPS {
            STEP NATURAL_LANGUAGE {
                INTENT "Generate and assign a unique new Track Number.";
                DESCRIPTION "The system generates a unique track number not currently in use and assigns it to the newly decorrelated local track. The resulting TN is provided via the global state 'Generated_New_TN' for retrieval.";
            };
        }
    }

    PROCEDURE Atomic_EstablishOriginalTNAsRemote "Sets the original track as a remote track." {
        STEPS {
            STEP "Establish TN A as a remote track in the local system.";
        }
    }
}