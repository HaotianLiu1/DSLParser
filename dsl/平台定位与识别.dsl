FUNCTION_MODEL PPLI_Location_And_Status_Maintenance {
    // 该模型描述了Link 16网络中，单元如何通过广播PPLI报文来报告位置，
    // 以及C2单元如何基于这些报文的接收情况来维持对网络参与者状态的认知。

    // 1. 参与者定义
    ACTORS {
        C2_JU_Monitor: C2_JU;     // 负责监控网络状态的指挥控制单元
        Reporting_JU: NON_C2_JU;  // 执行周期性PPLI报告的非指挥控制单元
    }

    // 2. 消息定义
    // 根据功能特异性，将J2.0与通用的J2.X分开定义
    MESSAGES {
        J2.X;       // 通用PPLI报文, 代表由JU为自身发送的PPLI (如J2.2, J2.3等)
        J2.0;       // 间接接口单元PPLI报文, 由FJU为被前伸的单元发送
    }

    // 3. 全局状态声明
    STATES {
        Is_JU_Mobile: BOOLEAN = TRUE;                      // 状态：Reporting_JU是否为移动单元
        Is_JU_Antenna_Displaced: BOOLEAN = FALSE;          // 状态：Reporting_JU的天线是否与其平台异地部署
        Monitored_JU_Status: ENUM {ACTIVE=1, INACTIVE=0} = ACTIVE; // 状态：C2单元监控下的JU状态
    }

    //--------------------------------------------------------------------------------
    //-- 原子流程 (Atomic Procedures)
    //-- 定义了模型中最基础、不可再分的动作，不包含任何逻辑判断。
    //--------------------------------------------------------------------------------

    PROCEDURE Atomic_Enrich_PPLI_With_Motion() "Enriches a PPLI message with motion data." {
        STEPS {
            STEP NATURAL_LANGUAGE {
                INTENT "Enrich PPLI with motion data.";
                ACTORS Reporting_JU;
                DATA_CONTEXT "Internal navigation system data (course, speed).";
                DESCRIPTION "The mobile JU shall include its current course and speed in the J2.X message. The position reported is extrapolated to the time of transmission.";
            };
        }
    }

    PROCEDURE Atomic_Report_Displaced_Position() "Reports the actual unit position for a displaced antenna." {
        STEPS {
            STEP NATURAL_LANGUAGE {
                INTENT "Report actual unit position for displaced antenna.";
                ACTORS Reporting_JU;
                DATA_CONTEXT "J2.X message content and Displaced Position continuation word.";
                DESCRIPTION "Set the Displaced Position Indicator in the J2.X message and transmit the applicable J2 Displaced Position continuation word to indicate the JU's actual location.";
            };
        }
    }

    PROCEDURE Atomic_Update_Track_File(unit: STRING, status: STRING) "Updates the track file for a given unit to a new status." {
        STEPS {
            STEP NATURAL_LANGUAGE {
                INTENT "Update the internal track file status for a monitored unit.";
                ACTORS C2_JU_Monitor;
                DESCRIPTION "The C2_JU_Monitor updates its internal track database, marking the specified unit with the new status (e.g., 'ACTIVE', 'INACTIVE').";
            };
        }
    }
    
    //--------------------------------------------------------------------------------
    //-- 子流程 (Sub-Procedures)
    //-- 封装了具有特定战术逻辑的、可复用的流程片段，包含逻辑控制。
    //--------------------------------------------------------------------------------

    PROCEDURE Sub_JU_Periodic_Reporting() "Manages the continuous, periodic transmission of PPLI messages by a JU." {
        STEPS {
            // 封装了周期性报告的完整循环逻辑
            WHILE Reporting_JU.STATUS == ACTIVE DO {
                // 调用组合流程来构建和发送报文
                CALL Sub_Compose_And_Transmit_JU_PPLI();
                // 等待下一个报告周期
                WAIT FOR 12 SECONDS {
                    ON "Next reporting cycle triggered" THEN {
                        CONTINUE;
                    }
                }
            }
        }
    }
    
    PROCEDURE Sub_Compose_And_Transmit_JU_PPLI() "Composes the full PPLI message based on unit status and transmits it." {
        STEPS {
            // 步骤一: 发送基础PPLI报文
            CALL Link16_Control_Handover_Detailed.Sub_SendMessage(
                Sender = Reporting_JU,
                MessageType = "J2.X",
                Params = {
                    // PPLI消息需要填充具体参数，例如位置、TQ等
                    // 这里使用空字典作为占位符，反映原始原子流程的简化
                },
                Mode = "BROADCAST",
                Recipient = NULL,
                ToAddress = NULL
            );

            // 步骤二: 根据单元状态，决定是否补充额外信息
            // 如果单元是移动的，则调用原子流程来补充航向和速度信息。
            IF Is_JU_Mobile == TRUE THEN {
                CALL Atomic_Enrich_PPLI_With_Motion();
            }
            
            // 如果单元的天线与其平台主体是异地部署的，则必须报告单元主体的真实位置。
            IF Is_JU_Antenna_Displaced == TRUE THEN {
                CALL Atomic_Report_Displaced_Position();
            }
        }
    }

    PROCEDURE Sub_C2JU_Continuous_Monitoring() "Manages the continuous monitoring of a JU's PPLI reports." {
        STEPS {
            // 启动初始的定时器
            C2_JU_Monitor START_TIMER Watchdog_Timer FOR 60 SECONDS;
            
            // 封装了持续监控的完整循环逻辑
            WHILE C2_JU_Monitor.STATUS == ACTIVE DO {
                WAIT {
                    // 情况一：成功收到PPLI报文
                    ON MESSAGE_RECEIVED J2.X FROM Reporting_JU THEN {
                        // 如果单元之前已被标记为非活动，现在收到报文，则将其恢复为活动。
                        IF Monitored_JU_Status != ACTIVE THEN {
                            ASSIGN Monitored_JU_Status = ACTIVE;
                            CALL Atomic_Update_Track_File(unit=Reporting_JU, status="ACTIVE");
                        }
                        // 重置定时器以开始新的监控周期
                       C2_JU_Monitor RESET_TIMER Watchdog_Timer;
                    }
                    // 情况二：定时器超时
                    ON TIMEOUT THEN {
                        // 调用超时处理子流程
                        CALL Sub_Handle_PPLI_Timeout();
                        // 发生超时后，此监控任务终止
                        TERMINATE;
                    }
                }
            }
        }
    }

    PROCEDURE Sub_Handle_PPLI_Timeout() "Handles the decision-making process when a PPLI timeout occurs." {
        STEPS {
            // 步骤一: 自动执行状态变更和通知。
            ASSIGN Monitored_JU_Status = INACTIVE;
            CALL Atomic_Update_Track_File(unit=Reporting_JU, status="INACTIVE");
            STEP C2_JU_Monitor NOTIFY "Unit has been marked as INACTIVE due to PPLI timeout." TO Operator;

            // 步骤二: 可选的后续处置决策，征求操作员是否要采取进一步行动。
            USER_CONFIRM "Take further action on the inactive unit (e.g., Delete or Initiate Surveillance)?" THEN {
                // 如果操作员选择“是”，则进入下一步，从两个具体行动中选择。
                USER_CONFIRM "Select action: Delete Track (Yes) or Initiate Surveillance (No)?" THEN {
                    // 情况一：操作员选择删除航迹
                    STEP NATURAL_LANGUAGE {
                        INTENT "Delete the track of the inactive unit.";
                        ACTORS C2_JU_Monitor;
                        DESCRIPTION "The operator chose to delete the track. The C2 JU removes the corresponding track from its surveillance display and database.";
                    };
                }
                ELSE {
                    // 情况二：操作员选择发起监视航迹
                    STEP NATURAL_LANGUAGE {
                        INTENT "Initiate a surveillance track for the inactive unit.";
                        ACTORS C2_JU_Monitor;
                        DESCRIPTION "The operator chose to initiate a new surveillance track. The C2 JU begins transmitting a surveillance track based on its own sensor data or as a non-real-time track.";
                    };
                }
            }
            // 此处没有ELSE块。如果第一个USER_CONFIRM的结果是“否”，则不执行任何操作。
            // 这代表了第三种选择：操作员决定暂时不进行任何处置，让该单元的航迹保持“INACTIVE”状态。
        }
    }
    
    //--------------------------------------------------------------------------------
    //-- 核心流程 (Core Procedure)
    //-- 作为顶层协调者，启动并行的后台任务。
    //--------------------------------------------------------------------------------

    PROCEDURE Core_PPLI_Network_Operation() "Initiates and orchestrates the parallel PPLI reporting and monitoring processes." {
        
        // 触发器：当网络成功建立，各单元完成入网后启动整个功能
        TRIGGER "Network Entry Complete";
        
        STEPS {
            // 核心流程的职责是启动并行的、持续运行的子流程。
            // PARALLEL准确地描述了报告和监控这两个任务是同时、独立进行的。
            PARALLEL {
                // 分支一：启动报告单元的周期性报告任务
                BRANCH {
                    CALL Sub_JU_Periodic_Reporting();
                }

                // 分支二：启动指挥控制单元的持续监控任务
                BRANCH {
                    CALL Sub_C2JU_Continuous_Monitoring();
                }
            }
        }
        
        EXCEPTION {
            // 这是一个基于系统健壮性推断的异常处理，用于应对网络完全中断的场景。
            ON Reporting_JU.STATUS == INACTIVE AND C2_JU_Monitor.STATUS == INACTIVE THEN {
                STEP C2_JU_Monitor NOTIFY "Network connection lost. Terminating process." TO System_Log;
                TERMINATE;
            }
        }
    }
}