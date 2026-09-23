parser grammar CreoleParser;

options { tokenVocab=CreoleLexer; }

document
    : SEA_WS? (element SEA_WS?)+ EOF
    ;

element
	: TAG_OPEN tag=TAG_B TAG_CLOSE content TAG_OPEN TAG_SLASH TAG_B TAG_CLOSE # formatting
	| TAG_OPEN TAG_BLOCK attributes TAG_CLOSE content TAG_OPEN TAG_SLASH TAG_BLOCK TAG_CLOSE # block
    | TAG_OPEN TAG_BR TAG_SLASH_CLOSE # lineBreak
	| TAG_OPEN tag=TAG_CI TAG_CLOSE content TAG_OPEN TAG_SLASH TAG_CI TAG_CLOSE # formatting
	| TAG_OPEN tag=TAG_GRANDTOTAL TAG_CLOSE content TAG_OPEN TAG_SLASH TAG_GRANDTOTAL TAG_CLOSE # formatting
	| TAG_OPEN tag=TAG_I TAG_CLOSE content TAG_OPEN TAG_SLASH TAG_I TAG_CLOSE # formatting
    | TAG_OPEN TAG_INCLUDE attribute TAG_SLASH_CLOSE # include
	| TAG_OPEN tag=TAG_MODEL TAG_CLOSE content TAG_OPEN TAG_SLASH TAG_MODEL TAG_CLOSE # formatting
	| TAG_OPEN tag=TAG_PRE TAG_CLOSE content TAG_OPEN TAG_SLASH TAG_PRE TAG_CLOSE # formatting
	| TAG_OPEN tag=TAG_P TAG_CLOSE content TAG_OPEN TAG_SLASH TAG_P TAG_CLOSE # paragraph
	| TAG_OPEN tag=TAG_PVAL TAG_CLOSE content TAG_OPEN TAG_SLASH TAG_PVAL TAG_CLOSE # formatting
	| TAG_OPEN TAG_REPORT TAG_CLOSE content TAG_OPEN TAG_SLASH TAG_REPORT TAG_CLOSE # report
	| TAG_OPEN tag=TAG_SCORE TAG_CLOSE content TAG_OPEN TAG_SLASH TAG_SCORE TAG_CLOSE # formatting
	| TAG_OPEN tag=TAG_SUB TAG_CLOSE content TAG_OPEN TAG_SLASH TAG_SUB TAG_CLOSE # formatting
	| TAG_OPEN tag=TAG_SUBTITLE TAG_CLOSE content TAG_OPEN TAG_SLASH TAG_SUBTITLE TAG_CLOSE # formatting
	| TAG_OPEN tag=TAG_SUBTOTAL TAG_CLOSE content TAG_OPEN TAG_SLASH TAG_SUBTOTAL TAG_CLOSE # formatting
	| TAG_OPEN tag=TAG_SUP TAG_CLOSE content TAG_OPEN TAG_SLASH TAG_SUP TAG_CLOSE # formatting
	| TAG_OPEN TAG_TABLE TAG_CLOSE content TAG_OPEN TAG_SLASH TAG_TABLE TAG_CLOSE # table
	| TAG_OPEN TAG_TD colspan=attribute? TAG_CLOSE content TAG_OPEN TAG_SLASH TAG_TD TAG_CLOSE # tableDetail
	| TAG_OPEN TAG_TH colspan=attribute? TAG_CLOSE content TAG_OPEN TAG_SLASH TAG_TH TAG_CLOSE # tableHeader
	| TAG_OPEN tag=TAG_TITLE TAG_CLOSE content TAG_OPEN TAG_SLASH TAG_TITLE TAG_CLOSE # formatting
	| TAG_OPEN TAG_TR TAG_CLOSE content TAG_OPEN TAG_SLASH TAG_TR TAG_CLOSE # tableRow
	| TAG_OPEN tag=TAG_U TAG_CLOSE content TAG_OPEN TAG_SLASH TAG_U TAG_CLOSE # formatting
	| TAG_OPEN tag=TAG_WARN TAG_CLOSE content TAG_OPEN TAG_SLASH TAG_WARN TAG_CLOSE # formatting
    ;

attributes
	: attribute+
	;

attribute
    : name=TAG_NAME TAG_EQUALS value=ATTVALUE_VALUE
    ;

content
    : inlineContent* (element inlineContent*)*
    ;

inlineContent
    : chardata
	| substitution
	| entity
    ;

substitution
	: EXPR_OPEN_SIMPLE path=EXPR_SIMPLE_VARIABLE # simpleSubstitution
	| EXPR_OPEN_COMPOUND path=EXPR_COMPOUND_VARIABLE EXPR_CLOSE_COMPOUND # simpleSubstitution
	| EXPR_OPEN_COMPOUND path=EXPR_COMPOUND_VARIABLE format=EXPR_COMPOUND_FORMAT EXPR_CLOSE_COMPOUND # compoundSubstitution
	;

chardata
    : TEXT # significantText
    | SEA_WS # significantText
    ;

entity
	: ENTITY_OPEN body=entityBody ENTITY_CLOSE
	;

entityBody
	: ENTITY_HEX # hexEntityBody
	| ENTITY_DECIMAL # decimalEntityBody
	| ENTITY_NAMED # namedEntityBody
	;