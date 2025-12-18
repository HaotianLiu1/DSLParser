import org.antlr.v4.runtime.tree.TerminalNode;

// 继承 Maven 插件自动生成的 BaseVisitor
public class Link16ModelVisitor extends Link16DSLBaseVisitor<Void> {

    @Override
    public Void visitFunctionModel(Link16DSLParser.FunctionModelContext ctx) {
        System.out.println("=== 解析功能模型: " + ctx.identifier().getText() + " ===");
        return visitChildren(ctx); // 继续遍历子节点
    }

    @Override
    public Void visitActorDeclaration(Link16DSLParser.ActorDeclarationContext ctx) {
        String name = ctx.identifier().getText();
        String type = ctx.actorType().getText();
        System.out.println("  [发现参与者] 名称: " + name + ", 类型: " + type);
        return null;
    }


    @Override
    public Void visitStep(Link16DSLParser.StepContext ctx) {
        // 简单打印步骤的内容
        System.out.print("    -> 步骤: ");

        if (ctx.action() != null) {
            // 如果是动作 (SENDS, BROADCASTS, NOTIFY)
            System.out.println(ctx.action().getText());
        } else if (ctx.naturalLanguageBlock() != null) {
            // 如果是自然语言块
            System.out.println("自然语言描述: " + ctx.naturalLanguageBlock().getText());
        } else if (ctx.STRING_LITERAL() != null) {
            // 如果是纯字符串描述
            System.out.println("描述: " + ctx.STRING_LITERAL().getText());
        } else {
            System.out.println("未知步骤内容");
        }
        return null;
    }

    @Override
    public Void visitAssignStatement(Link16DSLParser.AssignStatementContext ctx) {
        String target = ctx.accessExpression().getText();
        String expr = ctx.arithmeticExpression().getText();
        System.out.println("-> 赋值操作: " + target + " = " + expr);
        return null;
    }

    // 1. 处理 IF 语句，增加缩进或标记，体现逻辑分支
    @Override
    public Void visitIfStatement(Link16DSLParser.IfStatementContext ctx) {
        System.out.println("    [逻辑判断] IF " + ctx.conditionExpression().getText());

        // 访问 IF 块内的语句
        // 注意：这里只是简单遍历，实际项目中你可能需要维护一个"缩进级别"变量来美化输出
        for (Link16DSLParser.StatementContext stmt : ctx.statement()) {
            System.out.print("      |-- ");
            visit(stmt);
        }

        // 处理 ELSE IF
        for (Link16DSLParser.ElseIfPartContext elseIfCtx : ctx.elseIfPart()) {
            System.out.println("    [逻辑判断] ELSE IF " + elseIfCtx.conditionExpression().getText());
            for (Link16DSLParser.StatementContext stmt : elseIfCtx.statement()) {
                System.out.print("      |-- ");
                visit(stmt);
            }
        }

        // 处理 ELSE
        if (ctx.elsePart() != null) {
            System.out.println("    [逻辑判断] ELSE");
            for (Link16DSLParser.StatementContext stmt : ctx.elsePart().statement()) {
                System.out.print("      |-- ");
                visit(stmt);
            }
        }
        return null;
    }

    // 2. 处理 CALL 语句（之前漏掉的部分）
    @Override
    public Void visitCallStatement(Link16DSLParser.CallStatementContext ctx) {
        System.out.println("调用子流程: " + ctx.qualifiedIdentifier().getText());
        return null;
    }

    // 3. 更新 visitStatement，确保它能分发 Call 和 If
    @Override
    public Void visitStatement(Link16DSLParser.StatementContext ctx) {
        if (ctx.step() != null) {
            return visitStep(ctx.step());
        } else if (ctx.assignStatement() != null) {
            return visitAssignStatement(ctx.assignStatement());
        } else if (ctx.ifStatement() != null) {
            return visitIfStatement(ctx.ifStatement());
        } else if (ctx.callStatement() != null) {
            return visitCallStatement(ctx.callStatement());
        }
        // ... 其他语句类型 (Wait, Loop 等)
        return null;
    }

    // --- 补全消息定义 ---
    @Override
    public Void visitMessagesDef(Link16DSLParser.MessagesDefContext ctx) {
        System.out.println("\n[静态定义] 消息列表 (MESSAGES):");
        for (Link16DSLParser.MessageDeclarationContext msgCtx : ctx.messageDeclaration()) {
            System.out.println("  - " + msgCtx.messageName().getText());
        }
        return null;
    }

    // --- 补全枚举定义 ---
    @Override
    public Void visitDiscreteSet(Link16DSLParser.DiscreteSetContext ctx) {
        // ctx.identifier() 可能返回列表（如果有 FOR ... DOT ...），我们取第一个作为枚举名
        // 如果你的语法里 discreteSet : ENUM identifier ...
        // 那么 ctx.identifier(0) 或者 ctx.identifier() 都能拿到名字
        String enumName = ctx.identifier(0).getText();

        System.out.println("\n[静态定义] 枚举集合: " + enumName);

        for (Link16DSLParser.DiscreteValueContext valCtx : ctx.discreteValue()) {
            // ✅ 修正点：直接调用生成的 identifier() 方法，而不是去 children 里抓
            String name = valCtx.identifier().getText();
            String assignment = valCtx.valueAssignment().getText();
            String desc = valCtx.STRING_LITERAL().getText();

            System.out.println("  |-- " + name + " " + assignment + " (" + desc + ")");
        }
        return null;
    }

    // --- 补全全局状态 ---
    @Override
    public Void visitStateDeclaration(Link16DSLParser.StateDeclarationContext ctx) {
        System.out.print("\n[静态定义] 全局状态: " + ctx.identifier().getText());
        System.out.print(" (类型: " + ctx.dataType().getText() + ")");
        if (ctx.arithmeticExpression() != null) {
            System.out.print(" 默认值 = " + ctx.arithmeticExpression().getText());
        }
        System.out.println();
        return null;
    }

    // --- 补全映射表 ---
    @Override
    public Void visitMappingSet(Link16DSLParser.MappingSetContext ctx) {
        System.out.println("\n[静态定义] 映射表: " + ctx.identifier(0).getText());
        // 这里可以继续遍历 mapEntry
        return null;
    }

    @Override
    public Void visitProcedureDef(Link16DSLParser.ProcedureDefContext ctx) {
        String procName = ctx.identifier().getText();
        String desc = ctx.STRING_LITERAL().getText().replace("\"", "");

        System.out.println("\n[解析流程] " + procName + " (" + desc + ")");

        // ✅ 新增：检查并打印参数
        if (ctx.procedureParams() != null) {
            System.out.println("    (参数定义: " + ctx.procedureParams().getText() + ")");
        }

        // ✅ 新增：检查并打印触发器
        // 注意：G4定义中 trigger 是可选的，直接检查 token 是否存在或者 conditionExpression
        if (ctx.TRIGGER() != null) {
            // 找到 conditionExpression (它紧跟在 TRIGGER 后面)
            // 在你的 grammar 中: ( TRIGGER conditionExpression SEMI )?
            // 由于 ProcedureDef 下只有一个 conditionExpression 用于 Trigger，可以直接获取
            System.out.println("    [触发条件] " + ctx.conditionExpression().getText());
        }

        // 继续遍历 Steps (这会调用 visitSteps, visitStatement 等)
        // 注意：不要调用 visitChildren(ctx)，因为我们已经手动处理了头部信息
        // 直接访问 STEPS 块即可，或者只访问 steps 部分
        if (ctx.STEPS() != null) {
            for (Link16DSLParser.StatementContext stmt : ctx.statement()) {
                visit(stmt);
            }
        }

        return null;
    }


    // ========================================================================
    // 🆕 消息处理规则 (Message Handling Rules) Visitor 实现
    // ========================================================================

    // 1. 顶层入口
    @Override
    public Void visitTrRulesModel(Link16DSLParser.TrRulesModelContext ctx) {
        System.out.println("=== 解析消息收发规则模型 ===");
        return visitChildren(ctx);
    }

    // 2. 单个消息规则定义 (Message J3.2 Rules { ... })
    @Override
    public Void visitMessageRulesDef(Link16DSLParser.MessageRulesDefContext ctx) {
        String msgName = ctx.msgName().getText();
        System.out.println("\n[规则集] 针对消息: " + msgName);
        return visitChildren(ctx);
    }

    // 3. 发送规则块 (TransmitRules { ... })
    @Override
    public Void visitTransmitRules(Link16DSLParser.TransmitRulesContext ctx) {
        System.out.println("  |-- [发送规则组] (TransmitRules)");
        for (Link16DSLParser.TrRuleDefContext rule : ctx.trRuleDef()) {
            visit(rule);
        }
        return null;
    }

    // 4. 接收规则块 (ReceiveRules { ... })
    @Override
    public Void visitReceiveRules(Link16DSLParser.ReceiveRulesContext ctx) {
        System.out.println("  |-- [接收规则组] (ReceiveRules)");
        for (Link16DSLParser.TrRuleDefContext rule : ctx.trRuleDef()) {
            visit(rule);
        }
        return null;
    }

    // 5. 具体规则定义 (Rule "Name" { Condition: ... Action: ... })
    @Override
    public Void visitTrRuleDef(Link16DSLParser.TrRuleDefContext ctx) {
        // 获取规则名称 (去掉引号)
        String ruleId = "未命名规则";
        if (ctx.STRING_LITERAL(0) != null) { // 规则名是第一个 StringLiteral
            ruleId = ctx.STRING_LITERAL(0).getText().replace("\"", "");
        } else if (ctx.children.get(1).getText().startsWith("\"")) {
            // 备用获取方式，防止顺序变化
            ruleId = ctx.children.get(1).getText().replace("\"", "");
        }

        System.out.println("      |-- 规则: " + ruleId);

        // 提取条件 (Condition) - 获取对应子树的文本
        // 注意：这里为了日志简洁，直接打印表达式文本，如果不想要原始文本，可以继续 visitTrConditionExpression
        String condition = ctx.trConditionExpression().getText();
        System.out.println("          [条件]: " + condition);

        // 提取动作 (Action) - 它是最后一个 STRING_LITERAL
        // 根据语法: ACTION_KW COLON STRING_LITERAL RBRACE
        // 所以 Action 是最后一个 String Token
        int stringCount = ctx.STRING_LITERAL().size();
        if (stringCount > 0) {
            String action = ctx.STRING_LITERAL(stringCount - 1).getText().replace("\"", "");
            System.out.println("          [动作]: " + action);
        }

        return null;
    }


}