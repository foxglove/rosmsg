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
  INTEGER: /\d+/,
  COMMENT: /(?:\/\/[^\n]*)|(?:\/\*(?:.|\n)+?\*\/)/,
  HEX_LITERAL: /0x(?:[0-9a-fA-F])+?/,
  STRING: {match: /"(?:\\["\\rnu]|[^"\\])*"/, value: x => x.slice(1, -1)}, // remove outside quotes
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
  SIGN: /[+-]/,
  EQ: /=[^\n]*?/,
  NAME: {match: /[a-zA-Z_][a-zA-Z0-9_]*(?:\:\:[a-zA-Z][a-zA-Z0-9_]*)*/, type: moo.keywords(kwObject)},
});

// Ignore whitespace and comment tokens
const tokensToIgnore = ['SPACE', 'COMMENT'];
// requires us to override the lexer's next function 
lexer.next = (next => () => {
  let token;
  while ((token = next.call(lexer)) && tokensToIgnore.includes(token.type)) {}
  return token;
})(lexer.next);

// Utiility functions

const numericTypeMap = {
  "unsigned short": "uint16",
  "unsigned long": "uint32",
  "unsigned long long": "uint64",
  "short": "int16",
  "long": "int32",
  "long long": "int64",
  "double": "float32",
  "float": "float32",
  "long double": "float64",
  "octet": "byte",
  "wchar": "char",
};

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

  // handle %NAME token
  return d?.value ? constantToValueMap[d.value] : undefined;  
}

function processComplexModule(d) {
  const moduleName = d[0][2].name;
  const defs = d[0][4];
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
  const moduleName = d[0][2].name;
  const enclosedConstants = d[0][4];
  // need to return array here to keep same signature as processComplexModule
  return [{
    name: moduleName,
    definitions: enclosedConstants.flat(1),
  }];
}

%}

@lexer lexer

main -> importDcl:* module:+ {% d => {
  return d[1][0];
}
%}

# support <import> or "import" includes - just ignored
importDcl -> "#" "include" (%STRING | "<" %NAME ("/" %NAME):* "." "idl" ">") {% noop %}

# constant modules need to be separate from complex modules since they shouldn't mix
module  -> (multiAnnotations "module" fieldName "{" (constantDcl):+ "}" semi) {% processConstantModule %}
  | (multiAnnotations "module" fieldName "{" (structWithAnnotation|module):+ "}" semi) {% processComplexModule %}


structWithAnnotation -> multiAnnotations struct {% 
 // ignore annotations on structs because we can only read default value (which doesn't apply)
 d => {return d[1];}
%}

struct -> "struct" fieldName "{" (declaration):+ "}" semi {% d => {
  const name = d[1].name;
  const definitions = d[3].flat(2).filter(def => def !== null);
  return {
    name,
    definitions,
  };
} %}

constantDcl -> multiAnnotations constType semi {% d => d[1] %}
declaration -> fieldWithAnnotation semi {% d => d[0] %}

fieldWithAnnotation -> multiAnnotations fieldDcl {% d=> {
  let possibleAnnotations = [];
  if(d[0]) {
    possibleAnnotations = d[0];
  }
  const fields = d[1];
  const finalDefs = fields.map((def) => extend([...possibleAnnotations, def]));
  return finalDefs;
} %}

fieldDcl -> (
     allTypes  multiFieldNames arrayLength
   | allTypes multiFieldNames
   | sequenceType multiFieldNames
 ) {% (d) => {
  const names = d[0].splice(1, 1)[0];
  // create a definition for each name
  const defs = names.map((nameObj) => extend([...d[0], nameObj]));
  return defs
} %}

multiFieldNames -> fieldName ("," fieldName):* {%
 d => {
   const fieldNames = d.flat(2).filter( d => d !== null && d.name);
   return fieldNames;
 }
%}
   
multiAnnotations -> annotation:* {%
  d => {
    return d[0] ? d[0].filter(d => d !== null) : null;
  }
%}

annotation -> (
    defaultAnnotation
  | rangeAnnotation
  | commentAnnotation
  | keyAnnotation
  | transferModeAnnotation
  ) {% d => id(id(d)) %}

# ROS 2 spec only supports annotations mentioned here https://design.ros2.org/articles/idl_interface_definition.html 
defaultAnnotation -> at "default" "(" "value" assignment ")" {% d => { 
  return {defaultValue: d[4].value };
} %}

# These annotations will not cause errors, but are ignored in the message definition AST
# We can't support generic annotations because it would make this grammar ambiguous (give it multiple ways to parse the same input)
rangeAnnotation -> at "range" "(" "min" assignment "," "max" assignment ")" {% noop %}

commentAnnotation -> at "verbatim" "(" "language" assignment "," "text" %EQ STR ")" {% noop %}

keyAnnotation -> at "key" {% noop %}

transferModeAnnotation -> at "transfer_mode" "(" %NAME ")" {% noop %}

at -> "@" {% noop %}

constType -> (
     constKeyword numericType fieldName floatAssignment simple
   | constKeyword numericType fieldName intAssignment simple
   | constKeyword stringType fieldName stringAssignment simple
   | constKeyword booleanType fieldName booleanAssignment simple
) {% d => {
  const def = extend(d[0]);
  const name = def.name;
  const value = def.value;
  constantToValueMap[name] = value;
  return def;
} %}

constKeyword -> "const"  {% d => ({isConstant: true}) %}

fieldName -> %NAME {% d => ({name: d[0].value}) %}

  
sequenceType -> "sequence" "<" allTypes ("," (INT|%NAME) ):? ">" {% d => {
  const arrayUpperBound = d[3] !== null ? getIntOrConstantValue(d[3][1][0]) : undefined;
  const typeObj = d[2];
  return {
    ...typeObj,
    isArray: true, 
    arrayUpperBound,
  };
}%}

arrayLength -> "[" (INT|%NAME) "]" {%
  ([, intOrName]) => ({isArray: true, arrayLength: getIntOrConstantValue(intOrName ? intOrName[0] : undefined) }) 
%}

assignment -> (
    floatAssignment
  | intAssignment
  | stringAssignment
  | booleanAssignment
) {% d => d[0][0] %}

floatAssignment ->   %EQ (SIGNED_FLOAT | FLOAT) {% ([, num]) => ({valueText: num[0], value: parseFloat(num[0])}) %}
intAssignment -> %EQ (SIGNED_INT | INT) {% ([, num]) => ({valueText: num[0], value: parseInt(num[0])}) %}
stringAssignment -> %EQ STR {% ([, str]) => ({valueText: str, value: str}) %}
booleanAssignment -> %EQ BOOLEAN {% ([, bool]) => ({valueText: bool, value: bool === "TRUE"}) %}

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

stringType ->  ("string"|"wstring") ("<" (INT | %NAME) ">"):? {% d => {
  let strLength = undefined;
  if(d[1] !== null) {
    strLength = getIntOrConstantValue(d[1][1] ? d[1][1][0] : undefined);
  }
  return {type: "string", upperBound: strLength};
} %}

booleanType -> "boolean" {% d => ({type: "bool"}) %}

numericType -> (
    "byte"
  | "octet"
  | "wchar"
  | "char"
  | "long" "double"
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
  | "unsigned" "short"
  | "short"
  | "unsigned" "long" "long"
  | "long" "long"
  | "unsigned" "long"
  | "long" 
) {% (d) => { 
  const typeString = d[0].map((t) => t?.value).filter(t => !!t).join(" ");
  let type = numericTypeMap[typeString];
  return { type: type ? type : typeString }; ;
}
%}

# ALL CAPS return strings rather than objects or null (terminals)

BOOLEAN -> ("TRUE" | "FALSE") {% join %}

# need to support mutliple adjacent strings as a single string
STR -> %STRING:+  {% d => {
  return join(d.flat(1).filter(d => d !== null));
}%}

SIGNED_FLOAT -> ("+"|"-") FLOAT {% join %}

FLOAT -> (%DECIMAL|%DECIMALEXP) {% join %}
 | (%DECIMAL "d") {% d => d[0][0].value %}
 | (INT "d") {% d => d[0][0] %}


SIGNED_INT -> ("+"|"-") INT  {% join %}

# convert token to string so that its easier to work with
INT -> %INTEGER {% join %}

semi -> ";" {% noop %}

simple -> null {% () => ({isComplex: false}) %}

