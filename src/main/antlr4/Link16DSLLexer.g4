lexer grammar Link16DSLLexer;

// ============================================================================
// 1️⃣ 特殊函数名 (优先匹配)
// ============================================================================
HAS_R2_FOR                     : 'HAS_R2_FOR';
IS_CONTROLLING_UNIT_FOR        : 'IS_CONTROLLING_UNIT_FOR';
GET_NUMBER_OF_FIXES_FOR_AOP    : 'GET_NUMBER_OF_FIXES_FOR_AOP';
ATOMIC_LOG_TO_SYSTEM           : 'ATOMIC_LOG_TO_SYSTEM';

// ============================================================================
// 2️⃣ 关键字定义 (必须在 IDENTIFIER 之前！)
// ============================================================================
FUNCTION_MODEL : 'FUNCTION_MODEL';
TYPES          : 'TYPES';
ACTORS         : 'ACTORS';
MESSAGES       : 'MESSAGES'; // 注意：这是原来的 MESSAGES
DISCRETES      : 'DISCRETES';
STATES         : 'STATES';
MAPPINGS       : 'MAPPINGS';
PROCEDURE      : 'PROCEDURE';
PARTICIPANTS   : 'PARTICIPANTS';
TRIGGER        : 'TRIGGER';
STEPS          : 'STEPS';
STEP           : 'STEP';
REPEAT         : 'REPEAT';
IF             : 'IF';
ELSE_IF        : 'ELSE_IF';
ELSE           : 'ELSE';
THEN           : 'THEN';
FOR            : 'FOR';
OR             : 'OR';
AND            : 'AND';
NOT            : 'NOT';
CALL           : 'CALL';

// --- 事件与动作关键字 ---
MESSAGE_SENT     : 'MESSAGE_SENT';
MESSAGE_RECEIVED : 'MESSAGE_RECEIVED';
SENDS            : 'SENDS';
BROADCASTS       : 'BROADCASTS';
NOTIFY           : 'NOTIFY';

// --- 🆕 消息处理规则专用关键字 (新加的必须放在这里) ---
MESSAGE_KW      : 'Message';     // <--- 这里的顺序很重要！必须在 IDENTIFIER 之前
RULES           : 'Rules';
TRANSMIT_RULES  : 'TransmitRules';
RECEIVE_RULES   : 'ReceiveRules';
RULE_KW         : 'Rule';
CONDITION       : 'Condition';
ACTION_KW       : 'Action';
TEXT            : 'Text';
PLATFORM        : 'Platform';
ROLE            : 'Role';
CAPABILITY      : 'Capability';
ON_EVENT        : 'OnEvent';
RECEIPT_OF      : 'ReceiptOf';
SYSTEM_CUE      : 'SystemCue';
FIELD           : 'Field';
TIMING          : 'Timing';
IS              : 'is';
PERIODIC        : 'Periodic';
ON_UPDATE       : 'OnUpdate';
ON_DEMAND       : 'OnDemand';
HAS             : 'HAS';

// ---------------------------------------------------

TO             : 'TO';
TERMINATE      : 'TERMINATE';
CONTINUE       : 'CONTINUE';
ASSIGN         : 'ASSIGN';
ENUM           : 'ENUM';
STRUCT         : 'STRUCT';
MAP            : 'MAP';
MAP_STATE      : 'MAP_STATE';
FROM           : 'FROM';
IN_RANGE       : 'IN_RANGE';
TIMER_EXPIRED  : 'TIMER_EXPIRED';
TIMEOUT        : 'TIMEOUT';
WAIT           : 'WAIT';
ON             : 'ON';
EXCEPTION      : 'EXCEPTION';
USER_CONFIRM   : 'USER_CONFIRM';
TO_ADDRESS     : 'TO_ADDRESS';
SECONDS        : 'SECONDS';
MILLISECONDS   : 'MILLISECONDS';
WHILE          : 'WHILE';
DO             : 'DO';
BRANCH         : 'BRANCH';
PARALLEL       : 'PARALLEL';
START_TIMER    : 'START_TIMER';
STOP_TIMER     : 'STOP_TIMER';
RESET_TIMER    : 'RESET_TIMER';
TIMES          : 'TIMES';
OPTIONAL       : 'OPTIONAL';
OVERRIDE       : 'OVERRIDE';
PRIORITY       : 'PRIORITY';
MUST_SEND      : 'MUST_SEND';
MUST_BROADCAST : 'MUST_BROADCAST';
NATURAL_LANGUAGE : 'NATURAL_LANGUAGE';
INTENT         : 'INTENT';
DATA_CONTEXT   : 'DATA_CONTEXT';
DESCRIPTION    : 'DESCRIPTION';
RULE           : 'RULE';
HAS_FIELD      : 'HAS_FIELD';
TIME_SINCE     : 'TIME_SINCE';
STATUS         : 'STATUS';

// Types & Values
C2_JU            : 'C2_JU';
NON_C2_JU        : 'NON_C2_JU';
GENERIC_PLATFORM : 'GENERIC_PLATFORM';
NON_IU           : 'NON_IU';
BOOLEAN        : 'BOOLEAN';
INTEGER        : 'INTEGER';
FLOAT          : 'FLOAT';
STRING_TYPE    : 'STRING';
DICTIONARY     : 'DICTIONARY';
ACTOR          : 'ACTOR';
IN             : 'IN';
ADDRESS        : 'ADDRESS';
ACTIVE         : 'ACTIVE';
INACTIVE       : 'INACTIVE';
STANDBY        : 'STANDBY';

// ============================================================================
// 3️⃣ 运算符与符号
// ============================================================================
EQ      : '=';
DOT     : '.';
COMMA   : ',';
SEMI    : ';';
COLON   : ':';
LPAREN  : '(';
RPAREN  : ')';
LBRACE  : '{';
RBRACE  : '}';
LBRACKET : '[';  // 新加的
RBRACKET : ']';  // 新加的
ARROW   : '->';
PLUS    : '+';
MINUS   : '-';
STAR    : '*';
DIV     : '/';
EQ_EQ   : '==';
NE      : '!=';
GT      : '>';
LT      : '<';
GE      : '>=';
LE      : '<=';

J_TOKEN : 'J';
X_TOKEN : 'X';
C_TOKEN : 'C';
E_TOKEN : 'E';
J_MSG_ID : 'J' [0-9X]+ '.' [0-9X]+ ;

TRUE    : 'TRUE';
FALSE   : 'FALSE';
NULL_LIT: 'NULL';

// ============================================================================
// 4️⃣ 字面量
// ============================================================================
NUMBER  : [0-9]+ ('.' [0-9]+)?;
STRING_LITERAL : '"' ( '\\' . | ~["\\] )* '"';

// ============================================================================
// 5️⃣ 注释与空白
// ============================================================================
LINE_COMMENT : '//' ~[\r\n]* -> skip;
BLOCK_COMMENT : '/*' .*? '*/' -> skip;
WS : [ \u00A0\t\r\n]+ -> skip;

// ============================================================================
// 6️⃣ 普通标识符 (必须放在最后！！！)
// ============================================================================
IDENTIFIER : [a-zA-Z_] [a-zA-Z0-9_]* ;