@{%
const moo = require("moo");
const lexer = moo.compile({
  space: {match: /\s+/, lineBreaks: true},
  number: /-?(?:[0-9]|[1-9][0-9]+)(?:\.[0-9]+)?(?:[eE][-+]?[0-9]+)?\b/,
  doubleQuotedString: /"(?:\\.|[^"\\])*"/,
  singleQuotedString: /'(?:\\.|[^'\\])*'/,
  comment: /#[^\n]*/,
  '[': '[',
  ']': ']',
  ',': ',',
  '=': '=',
  '<=': '<=',
  fieldOrType: /[a-zA-Z][a-zA-Z0-9_]*(?:\/[a-zA-Z][a-zA-Z0-9_]*){0,2}/,
  plainString: /[^#\s\n][^\s\n]*/,
});

const STRING_ESCAPES = String.raw`\\(?<char>['"abfnrtv\\])|\\(?<oct>[0-7]{1,3})|\\x(?<hex2>[a-fA-F0-9]{2})|\\u(?<hex4>[a-fA-F0-9]{4})|\\U(?<hex8>[a-fA-F0-9]{8})`;

function parseStringLiteral(maybeQuotedStr) {
  let quoteThatMustBeEscaped = "";
   let str = maybeQuotedStr;
   for (const quote of ["'", '"']) {
     if (maybeQuotedStr.startsWith(quote)) {
       if (!maybeQuotedStr.endsWith(quote)) {
         throw new Error(`Expected terminating ${quote} in string literal: ${maybeQuotedStr}`);
       }
       quoteThatMustBeEscaped = quote;
       str = maybeQuotedStr.substring(quote.length, maybeQuotedStr.length - quote.length);
       break;
     }
   }
   if (
     !new RegExp(String.raw`^(?:[^\\${quoteThatMustBeEscaped}]|${STRING_ESCAPES})*$`).test(str) ==
     undefined
   ) {
     throw new Error(`Invalid string literal: ${str}`);
   }
  return str.replace(new RegExp(STRING_ESCAPES, "g"), (...args) => {
    const { char, oct, hex2, hex4, hex8 } = args[args.length - 1];
    const hex = hex2 ?? hex4 ?? hex8;
    if (char != undefined) {
      return {
        "'": "'",
        '"': '"',
        a: "\x07",
        b: "\b",
        f: "\f",
        n: "\n",
        r: "\r",
        t: "\t",
        v: "\v",
        "\\": "\\",
      }[char];
    } else if (oct != undefined) {
      return String.fromCodePoint(parseInt(oct, 8));
    } else if (hex != undefined) {
      return String.fromCodePoint(parseInt(hex, 16));
    } else {
      throw new Error("Expected exactly one matched group");
    }
  });
}
%}

@lexer lexer

main ->
    _ boolType arrayType __ field boolDefaultValue:? _ comment:? simple {% function(d) { return extend(d) } %}
  | _ numericType arrayType __ field numericDefaultValue:? _ comment:? simple {% function(d) { return extend(d) } %}
  | _ stringType arrayType __ field stringDefaultValue:? _ comment:? simple {% function(d) { return extend(d) } %}
  | _ timeType arrayType __ field _ comment:? simple {% function(d) { return extend(d) } %}
  | _ customType arrayType __ field _ comment:? complex {% function(d) { return extend(d) } %}
  | _ boolType __ constantField _ assignment _ boolConstantValue _ comment:? {% function(d) { return extend(d) } %}
  | _ numericType __ constantField _ assignment _ numericConstantValue _ comment:? {% function(d) { return extend(d) } %}
  | _ stringType __ constantField _ assignment _ stringConstantValue:? _ comment:? {% function(d) {
      d[7] = d[7] || { value: "", valueText: "" };
      return extend(d)
      } %}
  | comment {% function(d) { return null } %}
  | blankLine {% function(d) { return null } %}

# Types

boolType -> "bool" {% function(d) { return { type: d[0].value } } %}

numericType ->
   ("byte"
  | "char"
  | "float32"
  | "float64"
  | "int8"
  | "uint8"
  | "int16"
  | "uint16"
  | "int32"
  | "uint32"
  | "int64"
  | "uint64") {% function(d) { return { type: d[0][0].value } } %}

stringType -> ("wstring" | "string") upperBound:? {% function(d) { return { type: d[0][0].value, upperBound: d[1] ?? undefined } } %}

timeType -> ("time" | "duration" | "builtin_interfaces/Time" | "builtin_interfaces/Duration" | "builtin_interfaces/msg/Time" | "builtin_interfaces/msg/Duration") {% function(d) {
  const parts = d[0][0].value.split("/");
  const type = parts[parts.length - 1].toLowerCase();
  return { type };
} %}

customType -> %fieldOrType {% function(d, _, reject) {
  const PRIMITIVE_TYPES = [
    "bool",
    "byte",
    "char",
    "float32",
    "float64",
    "int8",
    "uint8",
    "int16",
    "uint16",
    "int32",
    "uint32",
    "int64",
    "uint64",
    "string",
    "wstring",
    "time",
    "duration",
    "builtin_interfaces/Time",
    "builtin_interfaces/Duration",
    "builtin_interfaces/msg/Time",
    "builtin_interfaces/msg/Duration",
  ];
  const type = d[0].value;
  if (PRIMITIVE_TYPES.includes(type)) return reject;
  return { type };
} %}

arrayType ->
    "[" _ "]" {% function(d) { return { isArray: true } } %}
  | "[" _ number _ "]" {% function(d) { return { isArray: true, arrayLength: d[2] } } %}
  | "[" _ upperBound _ "]" {% function(d) { return { isArray: true, arrayUpperBound: d[2] } } %}
  | _ {% function(d) { return { isArray: false } } %}

# Fields

field -> %fieldOrType {% function(d, _, reject) {
  const name = d[0].value;
  if (name.match(/^[a-z](?:_?[a-z0-9]+)*$/) == undefined) return reject;
  return { name };
} %}

constantField -> %fieldOrType {% function(d, _, reject) {
  const name = d[0].value;
  if (name.match(/^[A-Z](?:_?[A-Z0-9]+)*$/) == undefined) return reject;
  return { name, isConstant: true };
} %}

# Constant Values

boolConstantValue -> bool {% function(d) { return { value: d[0][0], valueText: d[0][1] } } %}

numericConstantValue -> number {% function(d) { return { value: d[0], valueText: String(d[0]) } } %}

stringConstantValue -> (doubleQuotedString | singleQuotedString | unQuotedString) {% function(d) { return { value: d[0][0], valueText: d[0][0] } } %}

# Default Values

boolDefaultValue -> __ (bool | boolArray) {% function(d) { return { defaultValue: d[1][0][0] } } %}

numericDefaultValue -> __ (number | numberArray) {% function(d) { return { defaultValue: d[1][0] } } %}

stringDefaultValue -> __ (doubleQuotedString | singleQuotedString | unQuotedString) {% function(d) { return { defaultValue: d[1][0] } } %}

boolArray ->
    "[" _ "]" {% function(d) { return [] } %}
  | "[" _ bool (_ "," _ bool):* _ "]" {% extractArray %}

numberArray ->
    "[" _ "]" {% function(d) { return [] } %}
  | "[" _ number (_ "," _ number):* _ "]" {% extractArray %}

# Basic Tokens

bool ->
    ("true" | "True" | "1") {% function(d) { return [true, d[0][0].text] } %}
  | ("false" | "False" | "0") {% function(d) { return [false, d[0][0].text] } %}

number -> %number {% function(d) { return parseFloat(d[0].value) } %}

doubleQuotedString -> %doubleQuotedString {% function(d) { return parseStringLiteral(d[0].value) } %}

singleQuotedString -> %singleQuotedString {% function(d) { return parseStringLiteral(d[0].value) } %}

unQuotedString -> unQuotedWord %space:? unQuotedString:? {% function(d) {
  let output = "";
  for( let word of d ) {
    if( word === null ) {
      continue;
      }
    if( typeof(word) !== 'string' ) {
      output += word.text;
    }
    else {
      output += word;
    }
  }
  return parseStringLiteral(output);
} %}

unQuotedWord -> %fieldOrType {% function(d) {
  return d[0].value;
} %}

unQuotedWord -> %plainString {% function(d) { return parseStringLiteral(d[0].value); } %}

# <=N
upperBound -> "<=" number {% function(d) { return d[1] } %}

# =
assignment -> "=" {% function(d) { return null } %}

# Comments
comment -> %comment {% function(d) { return null } %}

# Line containing only whitespace
blankLine -> _ {% function(d) { return null } %}

# Optional whitespace
_ -> (null | %space) {% function(d) { return null } %}

# Required whitespace
__ -> %space {% function(d) { return null } %}

# Mark primitive types
simple -> null {% function() { return { isComplex: false } } %}

# Mark non-primitive types
complex -> null {% function() { return { isComplex: true } } %}

@{%
function extend(objs) {
  return objs.reduce((r, p) => ({ ...r, ...p }), {});
}

function extractArray(d) {
    const output = [d[2]];
    for (let i in d[3]) {
        output.push(d[3][i][3]);
    }
    return output;
}
%}
