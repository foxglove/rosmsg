@{%

// necessary to use keywords to avoid using the `reject` postprocessor which can cause poor perf
const keywords = [
  , "struct"
  , "module"
  , "const"
  , "include"

  //types
  , "boolean"
  , "wstring"
  , "string"
  , "sequence"
	
  // numeric types
  , "byte"
  , "octet"
  , "wchar"
  , "char"
  , "double"
  , "float"
  , "int8"
  , "uint8"
  , "int16"
  , "uint16"
  , "int32"
  , "uint32"
  , "int64"
  , "uint64"
  , "unsigned" 
  , "short"  
  , "long"
];

const kwObject = keywords.reduce((obj, w) => {
	obj[w] = w;
	return obj;
}, {});

const moo = require("moo");
const lexer = moo.compile({
  SPACE: {match: /\s+/, lineBreaks: true},
  DIGIT: /[0-9]/,
  COMMENT: /(?:\/\/[^\n]*)|(?:\/\*(?:.|\n)+?\*\/)/,
  HEX_LITERAL: /0x(?:[0-9][a-f][A-F])+?/,
  STRING: [{match: /"(?:\\["\\rnu]|[^"\\])*?"/, lineBreaks: true, value: x => x.slice(1, -1)}], // remove outside quotes
  LCBR: '{',
  RCBR: '}',
  LBR: '[',
  RBR: ']',
  LT: '<',
  GT: '>',
  LPAR: '(',
  RPAR: ')',
  ';': ';',
  ',': ',',
  at: '@',
  pnd: '#',
  pt: ".",
  '/': "/",
  sign: /[+|-]/,
  EQ: /=[^\n]*?/,
  name: {match: /[a-zA-Z_][a-zA-Z0-9_]*(?:\:\:[a-zA-Z][a-zA-Z0-9_]*)*/, type: moo.keywords(kwObject)},
});

%}

@lexer lexer

@{%
function join(d){
	return d.join("");
}
function extend(objs) {
  return objs.reduce((r, p) => ({ ...r, ...p }), {});
}

function noop() {
	return null;
}

const constantToValueMap = {};

function getIntOrConstantValue(d) {
	const int = parseInt(d);
	if(!isNaN(int)) {
		return int
	}

	// handle %name value
	return d?.value ? constantToValueMap[d.value] : undefined;	
}


function processComplexModule(d) {
	  const moduleName = d[0][4].name;
	  const defs = d[0][8];
	  const msgDefs = [];
	  function traverse(node, processNode) {
		  if(Array.isArray(node)) {
			  node.forEach(n => traverse(n, processNode));
		  } else {
			  processNode(node);
		  }
		  
	  }
	  traverse(d[0], (sub) => {
		  if(sub && sub.definitions) {
			  sub.name = `${moduleName}::${sub.name}`;
			  msgDefs.push(sub);
		  }
	  });
	  
	  
	  return msgDefs;
  }

function processConstantModule(d) {
	const moduleName = d[0][4].name;
    const enclosedConstants = d[0][8];
	return [{
		name: moduleName,
		definitions: enclosedConstants.flatMap(d => d),
	}];
}

%}


main -> (importDcl __):* module:+ _ {% d => {
	return d[1][0];
}
%}

importDcl -> _ "#" "include" __ (%STRING | "<" _ %name ("/" %name):* "." "idl" _ ">") {% noop %}

module  -> ((comment|annotation):* _ "module" __ fieldName __ "{" __ (constantDcl):+ __ "}" semi) {% processConstantModule %}
  | ((comment|annotation):* _ "module" __ fieldName __ "{" __ (structWithAnnotation|module):+ __ "}" semi) {% processComplexModule %}


structWithAnnotation -> (comment|annotation):* struct {% 
 // ignore annotations on structs because we can only read default value (which doesn't apply)
 d => {return d[1];}
%}

struct -> _ "struct" __ fieldName __ "{" __ (declaration):+ __ "}" semi {% d => {
	const name = d[3].name;
	const definitions = d[7].flatMap(d => d).filter(def => def !== null);
	return {
		name,
		definitions,
	};
} %}

constantDcl -> (comment|annotation):* constType semi {% d => d[1] %}
declaration -> fieldWithAnnotation semi {% d => d[0] %}

fieldWithAnnotation -> annotationOrCommentLines fieldDcl {% d=> {
	let possibleAnnotations = [];
	if(d[0]) {
		possibleAnnotations = d[0];
	}
	return extend([...possibleAnnotations, d[1]]);
} %}

fieldDcl -> 
     _ numericType __ fieldName arrayLength _  complex {% extend %}
   | _ stringType __ fieldName arrayLength _ complex {% extend %}
   | _ booleanType __ fieldName arrayLength _ complex {% extend %}
   | _ numericType __ fieldName _  simple {% extend %}
   | _ stringType __ fieldName _ simple {% extend %}
   | _ booleanType __ fieldName _ simple {% extend %}
   | _ sequenceType __ fieldName _ complex {% extend %}
   | _ customType __ fieldName _ complex {% extend %}
   
   
annotationOrCommentLines -> (annotation|comment):* {%
  d => {
	  return d[0][0] ? d[0][0].filter(d => d !== null) : null;
  }
%}

annotation -> (
    defaultAnnotation
  | rangeAnnotation
  | commentAnnotation
  | keyAnnotation
  | transferModeAnnotation
  ) {% d => id(id(d)) %}

defaultAnnotation -> _ at "default" _ "(" _ "value" assignment _ ")" {% d => { 
	return {defaultValue: d[7].value };
} %}

# unsupported annotations
rangeAnnotation -> _ at "range" _ "(" _ "min" assignment _ "," _ "max" assignment _ ")" {% noop %}

# can't use assignment variable 
commentAnnotation -> _ at "verbatim" _ "(" _ "language" assignment _ "," _ "text" _ %EQ _ STR ")" {% noop %}

keyAnnotation -> _ at "key" {% noop %}

transferModeAnnotation -> _ at "transfer_mode" _ "(" _ %name _ ")" {% noop %}

at -> "@" {% noop %}

comment -> _ %COMMENT {% noop %}


constType -> (
     _ constKeyword __ numericType __ fieldName assignment _ simple
   | _ constKeyword __ stringType __ fieldName assignment _ simple 
   | _ constKeyword __ booleanType __ fieldName assignment _ simple
) {% d => {
	const def = extend(d[0]);
	const name = def.name;
	const value = def.value;
	// can be used in defs to define lengths of arrays and strings
	constantToValueMap[name] = value;
	return def;
} %}

constKeyword -> "const"  {% d => ({isConstant: true}) %}

fieldName -> %name {% d => ({name: d[0].value}) %}

  
sequenceType -> "sequence" _ %LT _ primitiveTypes _ ("," _ (INT|%name) _ ):? %GT {% d => {
	const arrayUpperBound = d[6] !== null ? getIntOrConstantValue(d[6][2][0]) : undefined;
	const typeObj = d[4];
	return {
	  ...typeObj,
	  isArray: true, 
	  arrayUpperBound,
	};
}%}

arrayLength -> "[" _ (INT|%name) _ "]" {% d => ({isArray: true, arrayLength: getIntOrConstantValue(d[2] ? d[2][0] : undefined) }) %}

assignment -> 
    _ %EQ _ (SIGNED_FLOAT | FLOAT) {% ([_, __, ___,  num]) => ({valueText: num[0], value: parseFloat(num[0])}) %}
  | _ %EQ _ (SIGNED_INT | INT) {% ([_, __,___,  num]) => ({valueText: num[0], value: parseInt(num[0])}) %}
  | _ %EQ _ STR {% ([_, __, ___, str]) => ({valueText: str, value: str}) %}
  | _ %EQ _ BOOLEAN {% ([_, __, ___, bool]) => ({valueText: bool, value: bool === "TRUE"}) %}
  
primitiveTypes -> (
    stringType
  | numericType
  | booleanType
) {% d => id(id(d)) %}

customType -> %name {% d => ({type: d[0].value }) %}

stringType ->  ("string"|"wstring") (_ %LT _ (INT | %name) _ %GT):? {% d => {
	let strLength = undefined;
	if(d[1] !== null) {
		strLength = getIntOrConstantValue(d[1][3] ? d[1][3][0] : undefined);
	}
	return {type: "string", upperBound: strLength};
} %}
booleanType -> "boolean" {% d => ({type: "bool"}) %}

numericType -> (
    "byte"
  | "octet"
  | "wchar"
  | "char"
  | "long" __ "double"
  | "double"
  | "float"
  | "int8"
  | "uint8"
  | "int16"
  | "uint16"
  | "int32"
  | "uint32"
  | "int64"
  | "uint64"
  | "unsigned" __ "short"
  | "short"
  | "unsigned" __ "long" __ "long"
  | "long" __ "long"
  | "unsigned" __ "long"
  | "long" 
) {% function(d, reject) { 

	const maybeType = d[0].map((t) => t?.value).filter(t => !!t).join(" ");
	switch(maybeType) {
		case "unsigned short":
			return {type: "uint16"};
			
		case "unsigned long":
			return {type: "uint32"};
			
		case "unsigned long long":
			return {type: "uint64"};
			
		case "short":
			return {type: "int16"};
			
		case "long":
			return {type: "int32"};
			
		case "long long":
			return {type: "int64"};
			
		case "double":
		case "float":
			return {type: "float32"};
			
		case "long double":
			return {type: "float64"};
			
		case "octet":
			return {type: "byte"};
		
		case "wchar": 
			return {type: "char"};

		default:
			return { type: maybeType } ;
	}
}
%}

BOOLEAN -> ("TRUE" | "FALSE") {% join %}

STR -> (%STRING _):+  {% d => {
	return join(d[0].flatMap(d => d).filter(d => d !== null));
}%}

NUMBER -> (SIGNED_FLOAT | SIGNED_INT | FLOAT | INT)  {% join %}

# float = /-?\d+(\.\d+)?([eE][+-]?\d+)?/
SIGNED_FLOAT -> ("+"|"-") FLOAT {% join %}

FLOAT -> 
   (INT _EXP) {% d => join(d[0]) %}
 | (DECIMAL _EXP:?) {% d => join(d[0]) %}
 | (DECIMAL  "d") {% (d) => d[0][0] %} # ignore d since it can't be used for parseFloat
 | (INT  "d") {% (d) => d[0][0] %} # ignore d

_EXP -> ("e"|"E") (SIGNED_INT|INT) {% d => {
	return d.flatMap(d=>d).join("");
} %}

DECIMAL -> 
  (INT "." INT:?)  {% (d) => join(d[0])  %}
| ("." INT) {% (d) => join(d[0]) %}

SIGNED_INT -> ("+"|"-") INT  {% join %}

INT -> %DIGIT:+ {% ([digits]) => join(digits) %}

semi -> ";" {% noop %}


# Optional whitespace
_ -> (null | %SPACE) {% noop %}

# Required whitespace
__ -> %SPACE {% noop %}

# Mark primitive types
simple -> null {% function() { return { isComplex: false } } %}

# Mark non-primitive types
complex -> null {% function() { return { isComplex: true } } %}




