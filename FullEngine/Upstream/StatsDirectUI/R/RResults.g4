grammar RResults;

@parser::members
{
	protected const int EOF = Eof;
}

@lexer::members
{
	protected const int EOF = Eof;
	protected const int HIDDEN = Hidden;
}

/*
 * Parser Rules
 */

compileUnit returns [Dictionary<string, object> Values]
@init { $Values = new Dictionary<string, object>(); }
	: (stanza { foreach (KeyValuePair<string, object> pair in $stanza.Values) $Values[pair.Key] = pair.Value; })+ EOF
	;

stanza returns [Dictionary<string, object> Values]
	: nameAndData { $Values = $nameAndData.Values; }
	| charts { $Values = $charts.Values; }
	;

nameAndData returns [Dictionary<string, object> Values]
	: nameAndValues dataAndValues titleAndValues { $Values = CoalesceNamesAndValues($nameAndValues.Names, $dataAndValues.Values, $titleAndValues.Titles); }
	| nameAndValues dataAndValues { $Values = CoalesceNamesAndValues($nameAndValues.Names, $dataAndValues.Values, null); }
	;

charts returns [Dictionary<string, object> Values]
@init { $Values = new Dictionary<string, object>(); }
	: STARTGRAPHICS (chartRow { foreach (var kv in $chartRow.Values) $Values.Add(kv.Key, kv.Value); })*
	;

chartRow returns [Dictionary<string, object> Values]
@init { $Values = new Dictionary<string, object>(); }
	: STRING EQUALS path { $Values.Add(ToStringBody($STRING.text), PathToChart($path.Path)); }
	| path { $Values.Add(PathToName($path.Path), PathToChart($path.Path)); }
	;

path returns [string Path]
	: STRING { $Path = ToStringBody($STRING.text); }
	;

nameAndValues returns [List<string> Names]
	: STARTNAMES { $Names = new List<string>(); } (IDENTIFIER { $Names.Add($IDENTIFIER.text); })*
	;

dataAndValues returns [List<object> Values]
	: STARTDATA { $Values = new List<object>(); } (expression { $Values.Add($expression.Value); })*
	;

titleAndValues returns [List<string> Titles]
	: STARTTITLES { $Titles = new List<string>(); } (STRING { $Titles.Add(ToStringBody($STRING.text)); })*
	;

expression returns [object Value]
	: term { $Value = $term.Value; }
	| vector { $Value = $vector.Terms; }
	;

term returns [object Value]
	: INTEGER { $Value = int.Parse($INTEGER.text, System.Globalization.CultureInfo.InvariantCulture); }
	| FLOAT { $Value = double.Parse($FLOAT.text, System.Globalization.CultureInfo.InvariantCulture); }
	| STRING { $Value = ToStringBody($STRING.text); }
	| NA { $Value = null; }
	;

vector returns [List<object> Terms]
	: STARTVECTOR {$Terms = new List<object>(); } (term { $Terms.Add($term.Value); } COMMA? )* RPAREN
	; 

/*
 * Lexer Rules
 */

INTEGER :	('0'..'9')+
    ;

FLOAT
    :   SIGN? ('0'..'9')+ '.' ('0'..'9')* EXPONENT?
    |   SIGN? '.' ('0'..'9')+ EXPONENT?
    |   SIGN? ('0'..'9')+ EXPONENT
    ;

COMMA		: ',';
DIRSEP		: '\\'|'/';
DRIVE		: ('A'..'Z'|'a'..'z') ':';
EQUALS		: '=';
LPAREN		: '(';
NA			: 'N' 'A';
RPAREN		: ')';
STARTDATA	:	's' 't' 'a' 'r' 't' '~' 'd' 'a' 't' 'a';
STARTGRAPHICS:	's' 't' 'a' 'r' 't' '~' 'g' 'r' 'a' 'p' 'h' 'i' 'c' 's';
STARTNAMES	:	's' 't' 'a' 'r' 't' '~' 'n' 'a' 'm' 'e' 's';
STARTTITLES	:	's' 't' 'a' 'r' 't' '~' 't' 'i' 't' 'l' 'e' 's';
STARTVECTOR	:	'c' '(';

IDENTIFIER	: ('A'..'Z'|'a'..'z')('A'..'Z'|'a'..'z'|'0'..'9'|'.'|'!'|'$')*
	;

WS	
	: (' ' | '\t' | '\r' | '\n') -> skip
    ;

STRING
    :  '"' ( ~'"' )* '"'
    ;

fragment EXPONENT : ('d'|'D'|'e'|'E') ('+'|'-')? ('0'..'9')+ ;
fragment SIGN : ('+' | '-');