@{%

// necessary to use keywords to avoid using the `reject` postprocessor which can cause poor perf
// having these as keywords removes ambiguity with `customType` rule
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
// Terminal tokens are in all caps
const lexer = moo.compile({
  SPACE: {match: /\s+/, lineBreaks: true},
  DECIMALEXP: /(?:(?:\d+\.\d*)|(?:\d*\.\d+)|(?:[0-9]+))[eE](?:[+|-])?[0-9]+/,
  DECIMAL: /(?:(?:\d+\.\d*)|(?:\d*\.\d+))/,
  INTEGER: /[0-9]+/,
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
  AT: '@',
  PND: '#',
  PT: ".",
  '/': "/",
  SIGN: /[+|-]/,
  EQ: /=[^\n]*?/,
  NAME: {match: /[a-zA-Z_][a-zA-Z0-9_]*(?:\:\:[a-zA-Z][a-zA-Z0-9_]*)*/, type: moo.keywords(kwObject)},
});

// Utiility functions

// also used to parse tokens to strings since they start as an object
function join(d){
	return d.join("");
}

// used for combining AST components
function extend(objs) {
  return objs.reduce((r, p) => ({ ...r, ...p }), {});
}

function noop() {
	return null;
}

// Constants can be used in defs to define lengths of arrays and strings
// they should be defined before the def that uses them
const constantToValueMap = {};

function getIntOrConstantValue(d) {
	const int = parseInt(d);
	if(!isNaN(int)) {
		return int
	}

	// handle %NAME value
	return d?.value ? constantToValueMap[d.value] : undefined;	
}

function processComplexModule(d) {
  const moduleName = d[0][4].name;
  const defs = d[0][8];
  // returning array of message definitions
  const msgDefs = [];
  function traverse(node, processNode) {
    if(Array.isArray(node)) {
      node.forEach(n => traverse(n, processNode));
    } else {
      processNode(node);
    }
  }
  // Need to update the names of modules and structs to be in their respective namespaces
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
  // need to return array here to keep same signature as processComplexModule
	return [{
		name: moduleName,
		definitions: enclosedConstants.flat(1),
	}];
}

%}

@lexer lexer

main -> (importDcl __):* module:+ _ {% d => {
	return d[1][0];
}
%}

# support <import> or "import" includes - just ignored
importDcl -> _ "#" "include" __ (%STRING | "<" _ %NAME ("/" %NAME):* "." "idl" _ ">") {% noop %}

# constant modules need to be separate from complex modules since they shouldn't mix
module  -> ((comment|annotation):* _ "module" __ fieldName __ "{" __ (constantDcl):+ __ "}" semi) {% processConstantModule %}
  | ((comment|annotation):* _ "module" __ fieldName __ "{" __ (structWithAnnotation|module):+ __ "}" semi) {% processComplexModule %}


structWithAnnotation -> (comment|annotation):* struct {% 
 // ignore annotations on structs because we can only read default value (which doesn't apply)
 d => {return d[1];}
%}

struct -> _ "struct" __ fieldName __ "{" __ (declaration):+ __ "}" semi {% d => {
	const name = d[3].name;
	const definitions = d[7].flat(2).filter(def => def !== null);
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
  const fields = d[1];
	const finalDefs = fields.map((def) => extend([...possibleAnnotations, def]));
	return finalDefs;
} %}

fieldDcl -> (
     _ allTypes __  multiFieldNames arrayLength _
   | _ allTypes __ multiFieldNames _
   | _ sequenceType __ multiFieldNames _
 ) {% (d) => {
	const names = d[0].splice(3, 1)[0];
	// create a definition for each name
	const defs = names.map((nameObj) => extend([...d[0], nameObj]));
	return defs
} %}

multiFieldNames -> fieldName (_ "," __ fieldName):* {%
 d => {
	 const fieldNames = d.flat(2).filter( d => d !== null && d.name);
	 return fieldNames;
 }
%}
   
   
   
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

# unsupported annotations are ignored
rangeAnnotation -> _ at "range" _ "(" _ "min" assignment _ "," _ "max" assignment _ ")" {% noop %}

commentAnnotation -> _ at "verbatim" _ "(" _ "language" assignment _ "," _ "text" _ %EQ _ STR ")" {% noop %}

keyAnnotation -> _ at "key" {% noop %}

transferModeAnnotation -> _ at "transfer_mode" _ "(" _ %NAME _ ")" {% noop %}

at -> "@" {% noop %}

comment -> _ %COMMENT {% noop %}

constType -> (
     _ constKeyword __ numericType __ fieldName floatAssignment _ simple
   | _ constKeyword __ numericType __ fieldName intAssignment _ simple
   | _ constKeyword __ stringType __ fieldName stringAssignment _ simple
   | _ constKeyword __ booleanType __ fieldName booleanAssignment _ simple
) {% d => {
	const def = extend(d[0]);
	const name = def.name;
	const value = def.value;
	constantToValueMap[name] = value;
	return def;
} %}

constKeyword -> "const"  {% d => ({isConstant: true}) %}

fieldName -> %NAME {% d => ({name: d[0].value}) %}

  
sequenceType -> "sequence" _ "<" _ allTypes _ ("," _ (INT|%NAME) _ ):? ">" {% d => {
	const arrayUpperBound = d[6] !== null ? getIntOrConstantValue(d[6][2][0]) : undefined;
	const typeObj = d[4];
	return {
	  ...typeObj,
	  isArray: true, 
	  arrayUpperBound,
	};
}%}

arrayLength -> "[" _ (INT|%NAME) _ "]" {%
  d => ({isArray: true, arrayLength: getIntOrConstantValue(d[2] ? d[2][0] : undefined) }) 
%}

assignment -> (
    floatAssignment
  | intAssignment
  | stringAssignment
  | booleanAssignment
) {% d => d[0][0] %}

floatAssignment ->   _ %EQ _ (SIGNED_FLOAT | FLOAT) {% ([_, __, ___,  num]) => ({valueText: num[0], value: parseFloat(num[0])}) %}
intAssignment -> _ %EQ _ (SIGNED_INT | INT) {% ([_, __,___,  num]) => ({valueText: num[0], value: parseInt(num[0])}) %}
stringAssignment -> _ %EQ _ STR {% ([_, __, ___, str]) => ({valueText: str, value: str}) %}
booleanAssignment -> _ %EQ _ BOOLEAN {% ([_, __, ___, bool]) => ({valueText: bool, value: bool === "TRUE"}) %}

allTypes -> (
    primitiveTypes
  | customType
) {% d => d[0][0] %}

primitiveTypes -> (
    stringType
  | numericType
  | booleanType
) {% d => ({...d[0][0], isComplex: false}) %}

customType -> %NAME {% d => ({type: d[0].value, isComplex: true }) %}

stringType ->  ("string"|"wstring") (_ "<" _ (INT | %NAME) _ ">"):? {% d => {
	let strLength = undefined;
	if(d[1] !== null) {
		strLength = getIntOrConstantValue(d[1][3] ? d[1][3][0] : undefined);
	}
	return {type: "string", upperBound: strLength};
} %}

booleanType -> "boolean" {% d => ({type: "bool"}) %}

# order matters here
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

# ALL CAPS return strings rather than objects (terminals)

BOOLEAN -> ("TRUE" | "FALSE") {% join %}

# need to support mutliple adjacent strings as a single string
STR -> (%STRING _):+  {% d => {
	return join(d[0].flat(1).filter(d => d !== null));
}%}

# Not actually used due to needing to parse either an int or float from a string
NUMBER -> (SIGNED_FLOAT | SIGNED_INT | FLOAT | INT)  {% join %}

SIGNED_FLOAT -> ("+"|"-") FLOAT {% join %}

FLOAT -> (%DECIMAL|%DECIMALEXP) {% join %}
 | (%DECIMAL "d") {% d => d[0][0].value %}
 | (INT "d") {% d => d[0][0] %}


SIGNED_INT -> ("+"|"-") INT  {% join %}

INT -> %INTEGER {% join %}

semi -> ";" {% noop %}


# Optional whitespace
_ -> (null | %SPACE) {% noop %}

# Required whitespace
__ -> %SPACE {% noop %}

simple -> null {% () => ({isComplex: false}) %}


