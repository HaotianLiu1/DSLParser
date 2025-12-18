grammar Link16DSL;

options {
    tokenVocab=Link16DSLLexer;
}

// ==========================================
// 1. 顶层结构
// ==========================================
functionModel
    : FUNCTION_MODEL identifier LBRACE
        typesDef?
        actorsDef?
        messagesDef?
        discretesDef?
        stateDef?
        mappingsDef?
        (procedureDef | ruleDef)*
      RBRACE
    ;

// ==========================================
// 2-7. 定义块
// ==========================================
typesDef : TYPES LBRACE typeDefinition* RBRACE ;
typeDefinition : identifier COLON dataType SEMI ;

actorsDef : ACTORS LBRACE actorDeclaration* RBRACE ;
actorDeclaration : identifier COLON actorType SEMI ;
actorType : C2_JU | NON_C2_JU | GENERIC_PLATFORM | NON_IU ;

messagesDef : MESSAGES LBRACE messageDeclaration* RBRACE ;
messageDeclaration : messageName SEMI ;
messageName : J_MSG_ID wordSpecifier? | J_TOKEN numericOrWildcard DOT numericOrWildcard wordSpecifier? | identifier;
numericOrWildcard : NUMBER | X_TOKEN ;
wordSpecifier : ( C_TOKEN | E_TOKEN ) NUMBER ;

discretesDef : DISCRETES LBRACE discreteSet* RBRACE ;
discreteSet : ENUM identifier ( FOR messageName DOT identifier )? LBRACE discreteValue* RBRACE ;
discreteValue : identifier valueAssignment STRING_LITERAL SEMI ;
valueAssignment : EQ NUMBER | IN_RANGE LPAREN NUMBER COMMA NUMBER RPAREN ;

mappingsDef : MAPPINGS LBRACE mappingSet* RBRACE ;
mappingSet : MAP identifier LBRACE mapEntry* RBRACE | MAP_STATE identifier FROM event TO identifier ;
mapEntry : mapKey ARROW value SEMI ;
mapKey : value | LPAREN value ( COMMA value )* RPAREN ;

stateDef : STATES LBRACE stateDeclaration* RBRACE ;
stateDeclaration : identifier COLON dataType ( EQ arithmeticExpression )? SEMI ;

// ==========================================
// 8. 流程定义块
// ==========================================
procedureDef
    : PROCEDURE identifier procedureParams? STRING_LITERAL LBRACE
        ( TRIGGER conditionExpression SEMI )?
        STEPS LBRACE statement* RBRACE
        exceptionBlock?
      RBRACE
    ;

procedureParams : LPAREN paramDefList? RPAREN ;

statement
    : step
    | ifStatement
    | nullStatement
    | continueStatement
    | loopStatement
    | waitStatement
    | callStatement
    | parallelStatement
    | assignStatement
    | userInput
    | timerStatement
    ;

step
    : STEP stepModifier? ( action | naturalLanguageBlock | STRING_LITERAL ) SEMI
    ;

stepModifier : OPTIONAL | REPEAT NUMBER TIMES | OVERRIDE ;

// ✅ [核心修改] 动作规则
// SENDS 和 BROADCASTS 后面的括号改为 paramList (赋值/构造)
// 允许写法: SENDS J3.2(Speed=100) TO Target
action
    : identifier SENDS messageName ( LPAREN paramList RPAREN )? TO identifier
    | identifier BROADCASTS messageName ( LPAREN paramList RPAREN )? ( TO_ADDRESS arithmeticExpression )?
    | identifier NOTIFY arithmeticExpression TO identifier
    ;

naturalLanguageBlock
    : NATURAL_LANGUAGE LBRACE
        ( INTENT STRING_LITERAL SEMI )?
        ( ACTORS identifierList SEMI )?
        ( DATA_CONTEXT STRING_LITERAL SEMI )?
        ( DESCRIPTION STRING_LITERAL SEMI )?
      RBRACE
    ;

ifStatement : IF conditionExpression THEN LBRACE statement* RBRACE elseIfPart* elsePart? ;
elseIfPart : ELSE_IF conditionExpression THEN LBRACE statement* RBRACE ;
elsePart : ELSE LBRACE statement* RBRACE ;
nullStatement : TERMINATE SEMI ;
continueStatement : CONTINUE SEMI ;
loopStatement : WHILE conditionExpression DO LBRACE statement* RBRACE ;

waitStatement
    : WAIT ( FOR duration )? LBRACE
        onConditionClause*
      RBRACE
    ;

duration : NUMBER (SECONDS | MILLISECONDS) ;
onConditionClause : ON conditionExpression THEN LBRACE statement* RBRACE ;

callStatement : CALL qualifiedIdentifier ( LPAREN paramList? RPAREN )? SEMI ;
parallelStatement : PARALLEL LBRACE branchDef* RBRACE ;
branchDef : BRANCH LBRACE statement* RBRACE ;
assignStatement : ASSIGN accessExpression EQ arithmeticExpression SEMI ;
userInput : USER_CONFIRM STRING_LITERAL THEN LBRACE statement* RBRACE ( ELSE LBRACE statement* RBRACE )? ;

timerStatement : identifier timerAction SEMI ;
timerAction : START_TIMER identifier FOR duration | STOP_TIMER identifier | RESET_TIMER identifier ;
exceptionBlock : EXCEPTION LBRACE onConditionClause* RBRACE ;

ruleDef
    : RULE STRING_LITERAL PRIORITY NUMBER LBRACE
        ON event THEN LBRACE consequence* RBRACE
      RBRACE
    ;
consequence : ( MUST_SEND | MUST_BROADCAST ) arithmeticExpression ( LPAREN arithmeticExpression RPAREN )? SEMI ;

// ==========================================
// 10. 基础事件定义
// ==========================================
// ✅ [确认] 事件规则保持 conditionExpression (匹配/过滤)
// 允许写法: MESSAGE_RECEIVED J3.2(Speed > 100)
event
    : ( MESSAGE_SENT | MESSAGE_RECEIVED ) messageName ( LPAREN conditionExpression RPAREN )? ( FROM identifier )? ( TO identifier )?
    | STRING_LITERAL
    | TIMER_EXPIRED LPAREN identifier RPAREN
    | TIMEOUT
    ;

// ==========================================
// 11. 表达式体系
// ==========================================
conditionExpression : orExpr ;
orExpr : andExpr ( OR andExpr )* ;
andExpr : notExpr ( AND notExpr )* ;
notExpr : NOT notExpr | primaryCond ;
primaryCond : logicalAtom | LPAREN conditionExpression RPAREN ;
logicalAtom : comparison | event ;

comparison
    : arithmeticExpression compOp arithmeticExpression
    | arithmeticExpression IN LPAREN value ( COMMA value )* RPAREN
    | HAS_FIELD LPAREN messageName DOT identifier RPAREN
    | TIME_SINCE LPAREN event RPAREN GT duration
    | identifier DOT STATUS ( EQ_EQ | NE ) statusValue
    ;

compOp : EQ_EQ | NE | GT | LT | GE | LE ;
statusValue : ACTIVE | INACTIVE | STANDBY ;

arithmeticExpression : term ( ( PLUS | MINUS ) term )* ;
term : factor ( ( STAR | DIV ) factor )* ;

// ✅ Factor 包含 J_MSG_ID
factor
    : literal
    | accessExpression
    | J_MSG_ID
    | LPAREN arithmeticExpression RPAREN
    | dataStructLiteral
    ;

accessExpression : identifier accessSuffix* ;
accessSuffix : DOT identifier | LPAREN paramList? RPAREN ;
qualifiedIdentifier : identifier ( DOT identifier )* ;

// ==========================================
// 12. 数据类型体系
// ==========================================
dataType : primitiveType | compositeType | typeReference ;
primitiveType : BOOLEAN | INTEGER | FLOAT | STRING_TYPE | DICTIONARY ;
compositeType : structType | enumType ;
structType : STRUCT LBRACE structField* RBRACE ;
structField : identifier COLON dataType SEMI ;
enumType : ENUM LBRACE paramList RBRACE ;
typeReference : identifier ;

// ==========================================
// 13. 基础词法与字面量
// ==========================================
paramDefList : paramDef ( COMMA paramDef )* ;
paramDef : identifier COLON dataType ;

// ✅ ParamList 定义: 这里的 param 实际上是 name = value
paramList : param ( COMMA param )* ;
param : identifier EQ arithmeticExpression ;

identifierList : identifier ( COMMA identifier )* ;

// Link16DSL.g4 最底部

identifier
    : IDENTIFIER
    // --- 允许关键字作为标识符 (白名单) ---
    | ACTION_KW      // 允许 'Action'
    | STATUS         // 允许 'Status'
    | ROLE           // 允许 'Role'
    | CAPABILITY     // 允许 'Capability'
    | MESSAGE_KW     // 允许 'Message'
    | PLATFORM       // 允许 'Platform'
    | TEXT           // 允许 'Text'
    | FIELD          // 允许 'Field'
    | TIMING         // 允许 'Timing'
    // ✅ [新增] 状态值关键字 (修复本次报错)
    | ACTIVE
    | INACTIVE
    | STANDBY
    // ------------------------------------
    | HAS_R2_FOR
    | IS_CONTROLLING_UNIT_FOR
    | GET_NUMBER_OF_FIXES_FOR_AOP
    | ATOMIC_LOG_TO_SYSTEM
    | X_TOKEN
    ;

literal : NUMBER | STRING_LITERAL | booleanLiteral | nullLiteral ;
value : literal | identifier ;
booleanLiteral : TRUE | FALSE ;
nullLiteral : NULL_LIT ;

dataStructLiteral : LBRACE ( structEntry ( COMMA structEntry )* )? RBRACE ;
structEntry : identifier EQ arithmeticExpression ;


// ============================================================================
// 🆕 消息处理规则 DSL (Message Handling Rules)
// ============================================================================

// 1. 顶层入口
trRulesModel
    : messageRulesDef+
    ;

messageRulesDef
    : MESSAGE_KW msgName RULES LBRACE
        ruleBlock*
      RBRACE
    ;

// 复用 J_MSG_ID 或 J_TOKEN 组合
msgName
    : J_MSG_ID
    | STRING_LITERAL // 兼容 "J3.2" 写法
    | J_TOKEN numericOrWildcard DOT numericOrWildcard
    ;

// 2. 规则块
ruleBlock
    : transmitRules
    | receiveRules
    ;

transmitRules : TRANSMIT_RULES LBRACE trRuleDef* RBRACE ;
receiveRules  : RECEIVE_RULES LBRACE trRuleDef* RBRACE ;

// 3. 核心规则
trRuleDef
    : RULE_KW (STRING_LITERAL)? LBRACE
        CONDITION COLON trConditionExpression
        ACTION_KW COLON STRING_LITERAL
      RBRACE
    ;

// 4. 条件表达式 (处理优先级和递归)
trConditionExpression
    : trConditionTerm                                        # trTermExpr
    | NOT trConditionExpression                              # trNotExpr
    | trConditionExpression AND trConditionExpression        # trAndExpr
    | trConditionExpression OR trConditionExpression         # trOrExpr
    | LPAREN trConditionExpression RPAREN                    # trParenExpr
    ;

// 5. 条件原子
trConditionTerm
    : structuredCondition
    | naturalLanguageCondition
    ;

naturalLanguageCondition
    : TEXT LPAREN STRING_LITERAL RPAREN
    ;

// 扁平化的结构条件
structuredCondition
    : PLATFORM DOT (ROLE | CAPABILITY | STATUS) operator trValue    # condPlatform
    | ON_EVENT LPAREN trEventBody RPAREN                            # condEvent
    | FIELD LPAREN (msgName DOT)? identifier RPAREN operator trValue # condField
    | TIMING IS timingBody                                          # condTiming
    ;

trEventBody
    : RECEIPT_OF LPAREN msgName RPAREN
    | SYSTEM_CUE LPAREN STRING_LITERAL RPAREN
    ;

timingBody
    : PERIODIC LPAREN STRING_LITERAL RPAREN
    | ON_UPDATE
    | ON_DEMAND
    ;

// 辅助定义
operator
    : EQ_EQ | NE | GT | LT | GE | LE | IN | HAS
    ;

trValue
    : STRING_LITERAL
    | NUMBER
    | TRUE
    | FALSE
    | valueList
    ;

valueList
    : LBRACKET trValue (COMMA trValue)* RBRACKET
    ;