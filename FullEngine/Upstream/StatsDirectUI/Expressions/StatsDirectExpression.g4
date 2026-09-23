grammar StatsDirectExpression;

r returns [INode node]
	: EQ? expr { $node = $expr.node; } EOF
	;

expr returns [INode node]
	: lhs=expr op=(OR | DOUBLEBAR) rhs=andexpr { $node = new DyadicNode { Left = $lhs.node, Operator = DyadicOperator.Or, Right = $rhs.node }; }
	| andexpr { $node = $andexpr.node; }
	;

andexpr returns [INode node]
	: lhs=andexpr op=(AND | DOUBLEAMPERSAND) rhs=notexpr { $node = new DyadicNode { Left = $lhs.node, Operator = DyadicOperator.And, Right = $rhs.node }; }
	| notexpr { $node = $notexpr.node; }
	;

notexpr returns [INode node]
	: (NOT | EXCLAIM) rhs=notexpr { $node = new MonadicNode { Operator = MonadicOperator.Not, Node = $rhs.node }; }
	| relexpr { $node = $relexpr.node; }
	;

relexpr returns [INode node]
	: lhs=numexpr op=relop rhs=numexpr { $node = new DyadicNode { Left = $lhs.node, Operator = $op.operator, Right = $rhs.node }; }
	| numexpr { $node = $numexpr.node; }
	;

numexpr returns [INode node]
	: lhs=numexpr op=addop rhs=mulexpr { $node = new DyadicNode { Left = $lhs.node, Operator = $op.operator, Right = $rhs.node }; }
	| mulexpr { $node = $mulexpr.node; }
	;
	
mulexpr returns [INode node]
	: lhs=mulexpr op=mulop rhs=negexpr { $node = new DyadicNode { Left = $lhs.node, Operator = $op.operator, Right = $rhs.node }; }
	| negexpr { $node = $negexpr.node; }
	;

// Unary minus (and plus) on anything: -X1, -PI, -(3+2), -LOG(2), --5.  It binds less tightly than exponentiation and factorial,
// as the help's priority list says and as in Visual Basic and in written mathematics: -2^2 is -(2^2) = -4 and -3! is -(3!).
// Before version 5 a minus sign was only understood as part of a number, so -X1 could not be parsed and -2^2 was (-2)^2.
negexpr returns [INode node]
	: MINUS rhs=negexpr { $node = Negate($rhs.node); }
	| PLUS rhs=negexpr { $node = $rhs.node; }
	| powexpr { $node = $powexpr.node; }
	;

powexpr returns [INode node]
	: lhs=powexpr (CARET | STARSTAR) rhs=signedfactorial { $node = new DyadicNode { Left = $lhs.node, Operator = DyadicOperator.Pow, Right = $rhs.node }; }
	| factorial { $node = $factorial.node; }
	;

// The exponent may carry its own sign: 4^-2 is 4^(-2) = 0.0625, X1^-X2.
signedfactorial returns [INode node]
	: MINUS rhs=signedfactorial { $node = Negate($rhs.node); }
	| PLUS rhs=signedfactorial { $node = $rhs.node; }
	| factorial { $node = $factorial.node; }
	;

factorial returns [INode node]
	: term { $node = $term.node; }
	| term EXCLAIM { $node = new MonadicNode { Operator = MonadicOperator.Factorial, Node = $term.node }; }
	;
	
term returns [INode node]
	: INTEGER { $node = ParseInteger($INTEGER.text); }
	| FLOAT { $node = ParseFloat($FLOAT.text); }
	| STRING { $node = ParseString($STRING.text); }
	| LPAREN expr RPAREN { $node = $expr.node; }
	| constant { $node = $constant.node; }
	| function { $node = $function.node; }
	| IDENTIFIER { $node = ParseVariable($IDENTIFIER.text); }
	;
	
function returns [FunctionNode node]
	: functionName=IDENTIFIER LPAREN argumentlist RPAREN { $node = new FunctionNode { Name = $functionName.text.ToUpper(System.Globalization.CultureInfo.InvariantCulture), Arguments = $argumentlist.arguments }; }
	;
	
// Arguments are separated by a comma or, as in spreadsheets where the comma is the decimal separator, by a semicolon:
// PT(2,5; 10) is PT of 2.5 with 10 degrees of freedom there. The semicolon is accepted everywhere.
argumentlist returns [Arguments arguments]
	: lhs=arg { $arguments = new Arguments(); if (null != $lhs.argument) $arguments.Add($lhs.argument); }
	( (COMMA | SEMICOLON) rhs=arg { $arguments.Add($rhs.argument); }) *
	;
	
arg returns [Argument argument]
	: expr { $argument = new Argument { Node = $expr.node }; }
	| explicitParameterName GETS expr { $argument = new Argument { ExplicitParameterName = $explicitParameterName.text, Node = $expr.node }; }
	| { $argument = null; }
	;
	
constant returns [INode node]
	: PI { $node = new DoubleConstantNode { Constant = ParserConstant.Pi }; }
	| EE { $node = new DoubleConstantNode { Constant = ParserConstant.E }; }
	| FALSE { $node = new BooleanConstantNode { Constant = ParserConstant.False }; }
	| TRUE { $node = new BooleanConstantNode { Constant = ParserConstant.True }; }
	;
	
relop returns [DyadicOperator operator]
	: NE { $operator = DyadicOperator.NotEqual; }
	| LE { $operator = DyadicOperator.LessThanOrEqual; }
	| LT { $operator = DyadicOperator.LessThan; }
	| GE { $operator = DyadicOperator.GreaterThanOrEqual; }
	| GT { $operator = DyadicOperator.GreaterThan; }
	| EQ { $operator = DyadicOperator.Equal; }
	;

addop returns [DyadicOperator operator]
	: PLUS { $operator = DyadicOperator.Add; }
	| MINUS { $operator = DyadicOperator.Subtract; }
	;
	
mulop returns [DyadicOperator operator]
	: STAR { $operator = DyadicOperator.Multiply; }
	| SLASH { $operator = DyadicOperator.Divide; }
	| BACKSLASH { $operator = DyadicOperator.IntegerDivide; }
	| MOD { $operator = DyadicOperator.Modulo; }
	;

explicitParameterName
	: IDENTIFIER
	;

// Anything below here is lexical analysis

// A number is digits, an optional decimal separator and an optional exponent: no thousands separators. They used to be
// looked for (a comma, a point or a space, by locale, followed by three digits), which nobody types in a formula but which
// an argument list typed without spaces contains: PT(2,120) and PBINOM(3,100,0.5) stopped with a format error, and
// PT(10,120.25,0.5) was silently read as PT(10120.25, 0.5). A whole number written with separators never did work.
INTEGER :	DIGITS
    ;

// A decimal point may end a number (2. is 2) but a decimal comma may not: where the comma is the decimal separator
// "2," used to be taken as a number, so that PT(2, 10) could not be read at all.
FLOAT
    :   DIGITS DECIMALSEPARATOR ('0'..'9')+ EXPONENT?
    |   DIGITS TRAILINGPOINT EXPONENT?
    |   DECIMALSEPARATOR ('0'..'9')+ EXPONENT?
    |   DIGITS EXPONENT
    ;

// Tokens.  Implemented in this way to provide cheap, portable case-insensitivity.
AND	:	A N D;
EE	:	E E;
EQ	:	'=';
FALSE:	F A L S E;
GE	:	'=>' | '>=';
GETS:	':=';
GT	:	'>';
LE	:	'<=' | '=<';
LT	:	'<';
MOD	:	M O D;
NE	:	'<>' | '><';
NOT	:	N O T;
OR	:	O R;
PI	:	P I;
TRUE:	T R U E;

// LOG! (log factorial) is the only name with an exclamation mark. It used to be allowed inside any name, so X1! was read as a
// name and refused; it is now the factorial of X1.
IDENTIFIER: L O G '!' | FirstOfIdentifier (MiddleOfIdentifier* LastOfIdentifier)? ;

BACKSLASH	: '\\';
CARET		: '^';
COMMA		: ',';
SEMICOLON	: ';';
DOUBLEAMPERSAND: '&&';
DOUBLEBAR	: '||';
EXCLAIM		: '!';
LPAREN		: '(';
MINUS		: '-' | '\u2212';	// U+2212, the typographic minus sign that word processors and web pages use
PLUS		: '+'; 
RPAREN		: ')';
SLASH		: '/';
STARSTAR	: '*' '*';
STAR		: '*';

fragment FirstOfIdentifier : 'A'..'Z'|'a'..'z';
fragment MiddleOfIdentifier: 'A'..'Z'|'a'..'z'|'0'..'9'|'.';
fragment LastOfIdentifier:   'A'..'Z'|'a'..'z'|'0'..'9'|;

fragment A	:	'A'|'a';
fragment B	:	'B'|'b';
fragment C	:	'C'|'c';
fragment D	:	'D'|'d';
fragment E	:	'E'|'e';
fragment F	:	'F'|'f';
fragment G	:	'G'|'g';
fragment H	:	'H'|'h';
fragment I	:	'I'|'i';
fragment J	:	'J'|'j';
fragment K	:	'K'|'k';
fragment L	:	'L'|'l';
fragment M	:	'M'|'m';
fragment N	:	'N'|'n';
fragment O	:	'O'|'o';
fragment P	:	'P'|'p';
fragment Q	:	'Q'|'q';
fragment R	:	'R'|'r';
fragment S	:	'S'|'s';
fragment T	:	'T'|'t';
fragment U	:	'U'|'u';
fragment V	:	'V'|'v';
fragment W	:	'W'|'w';
fragment X	:	'X'|'x';
fragment Y	:	'Y'|'y';
fragment Z	:	'Z'|'z';


STRING
    :  '"' ( STRINGESCAPE | ~[\\"] )* '"'
    ;

fragment STRINGESCAPE
	: '\\"'
	| '\\\\'
	;

WS:     ( ' '
        | '\u00A0'
        | '\t'
        | '\r'
        | '\n'
        ) -> skip
    ;

fragment EXPONENT : ('d'|'D'|'e'|'E') ('+'|'-')? ('0'..'9')+ ;

fragment DIGITS
	: ('0'..'9')+
	;

fragment TRAILINGPOINT
	: {Separators != SeparatorStructure.DotComma}? '.'
	;

fragment DECIMALSEPARATOR
	: {Separators == SeparatorStructure.CommaDot || Separators == SeparatorStructure.SpaceDot}? '.'
	| {Separators == SeparatorStructure.DotComma}? ','
	;

// Any other character is an error. Without this rule the lexer dropped it without a word, so a typographic minus sign
// pasted from a document (U+2212, or an en dash) vanished and EXP of minus X1 was evaluated as EXP(X1). No parser rule
// accepts this token, so the parser reports the character.
ERRORCHAR : . ;
