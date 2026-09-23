lexer grammar CreoleLexer;

//
// Start in content mode - grab almost anything until we get something that drops us into another mode.
//
TAG_OPEN           : '<'  -> pushMode(TAG) ;
ENTITY_OPEN        : '&'  -> pushMode(ENTITY) ;
EXPR_OPEN_COMPOUND : '@{' -> pushMode(EXPR_COMPOUND) ;
EXPR_OPEN_SIMPLE   : '@'  -> pushMode(EXPR_SIMPLE) ;

SEA_WS             : (LineWhitespace* NewLine LineWhitespace*)+ -> skip;
TEXT               : ~('<'|'@'|'&')+ ;

//
// Entity declarations
//
mode ENTITY;

ENTITY_CLOSE    : ';' -> popMode ;

ENTITY_HEX      : '#x' HexDigit+ ;
ENTITY_DECIMAL  : '#' Digit+ ;
ENTITY_NAMED    : Letter (Letter|Digit)* ;

//
// Tag declarations
//
mode TAG;

// Closers and mode changes
TAG_CLOSE      : '>' -> popMode ;
TAG_SLASH_CLOSE: '/>' -> popMode ;
TAG_EQUALS     : '=' -> pushMode(ATTVALUE) ;
TAG_SLASH      : '/' ;

TAG_B          : 'b' ;
TAG_BLOCK      : 'block' ;
TAG_BR         : 'br' ;
TAG_CI         : 'ci' ;
TAG_GRANDTOTAL : 'grandtotal' ;
TAG_I          : 'i' ;
TAG_INCLUDE    : 'include' ;
TAG_MODEL      : 'model' ;
TAG_P          : 'p' ;
TAG_PRE        : 'pre' ;
TAG_PVAL       : 'pval' ;
TAG_REPORT     : 'report' ;
TAG_SCORE      : 'score' ;
TAG_SUB        : 'sub' ;
TAG_SUBTITLE   : 'subtitle' ;
TAG_SUBTOTAL   : 'subtotal' ;
TAG_SUP        : 'sup' ;
TAG_TABLE      : 'table' ;
TAG_TD         : 'td' ;
TAG_TH         : 'th' ;
TAG_TITLE      : 'title' ;
TAG_TR         : 'tr' ;
TAG_U          : 'u' ;
TAG_WARN       : 'warn' ;

// A useful catch-all to grab other tag names.  This will then fail at the parser.
TAG_NAME       : (Letter | Digit | '-' | '_' | '.' | MidDot | CombiningDiacriticalMark | Tie)+ ;

// Inside a tag, whitespace is ignored.
TAG_WHITESPACE : (' '|'\t'|'\r'|'\n')+ -> skip ;

//
// attribute values
//
mode ATTVALUE;

// an attribute value may have spaces between the '=' and the value
ATTVALUE_VALUE  : ' '* ATTRIBUTE -> popMode ;
ATTRIBUTE       : '"' ~('<'|'"')* '"' | '\'' ~[<']* '\'' ;

//
// Simple expressions - just grab the expression variable and go!
//
mode EXPR_SIMPLE;

EXPR_SIMPLE_VARIABLE : Expr_VariableName -> popMode ;

mode EXPR_COMPOUND;

EXPR_CLOSE_COMPOUND    : '}' -> popMode ;

EXPR_COMPOUND_FORMAT   : ':' ('default' | 'chart' | 'pval' | 'pval_half' | 'roundu' | 'roundx' | 'round0' | 'round1' | 'round2' | 'round3' | 'zvalp1' | 'zvalp2') ;
EXPR_COMPOUND_VARIABLE : Expr_VariableName ;

fragment
Expr_VariableName      : Letter (Letter | Digit | '-' | '_' | MidDot | CombiningDiacriticalMark | Tie)* ;

//
// Non-application specific below here.
//

fragment
LineWhitespace
    : ' '
    | '\t'
    ;

// Works with Mac, Unix, and Windows line endings.
fragment
NewLine
    : ('\r'|'\n')+
    ;

fragment
Letter
    : 'a'..'z'
    | 'A'..'Z'
    | '\u2070'..'\u218F'
    | '\u2C00'..'\u2FEF'
    | '\u3001'..'\uD7FF'
    | '\uF900'..'\uFDCF'
    | '\uFDF0'..'\uFFFD'
    ;

fragment
HexDigit
    : 'a'..'f'
    | 'A'..'F'
    | Digit
    ;

fragment
Digit
    : '0'..'9'
    ;

fragment
MidDot
    : '\u00B7'
    ;

fragment
CombiningDiacriticalMark
    : '\u0300'..'\u036F'
    ;

fragment
Tie
    : '\u203F'..'\u2040'
    ;