@{%
const moo = require("moo");
const lexer = moo.compile({
  space: {match: /\s+/, lineBreaks: true},
  number: /-?(?:[0-9]|[1-9][0-9]+)(?:\.[0-9]+)?(?:[eE][-+]?[0-9]+)?\b/,
  doubleQuotedString: /"(?:\\["bfnrt/\\]|\\u[a-fA-F0-9]{4}|[^"\\])*"/,
  singleQuotedString: /'(?:\\['bfnrt/\\]|\\u[a-fA-F0-9]{4}|[^'\\])*'/,
  comment: /#[^\n]*/,
  '[': '[',
  ']': ']',
  ',': ',',
  '=': '=',
  '<=': '<=',
  boolType: 'bool',
  numericType: /byte|char|float32|float64|int8|uint8|int16|uint16|int32|uint32|int64|uint64/,
  stringType: /w?string/,
  timeType: /time|duration/,
  true: /[Tt]rue/,
  false: /[Ff]alse/,
  fieldOrCustomType: /[a-zA-Z_]+(?:\/?[a-zA-Z0-9_]+)?/,
});
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
  | _ stringType __ constantField _ assignment _ stringConstantValue _ comment:? {% function(d) { return extend(d) } %}
  | comment {% function(d) { return null } %}
  | blankLine {% function(d) { return null } %}

# Types

boolType -> %boolType {% function(d) { return { type: d[0].value } } %}

numericType -> %numericType {% function(d) { return { type: d[0].value } } %}

stringType -> %stringType upperBound:? {% function(d) { return { type: d[0].value, upperBound: d[1] ?? undefined } } %}

timeType -> %timeType {% function(d) { return { type: d[0].value } } %}

customType -> %fieldOrCustomType {% function(d) { return { type: d[0].value } } %}

arrayType ->
    "[" _ "]" {% function(d) { return { isArray: true } } %}
  | "[" _ number _ "]" {% function(d) { return { isArray: true, arrayLength: d[2] } } %}
  | "[" _ upperBound _ "]" {% function(d) { return { isArray: true, arrayUpperBound: d[2] } } %}
  | _ {% function(d) { return { isArray: false } } %}

# Fields

field -> %fieldOrCustomType {% function(d, _, reject) {
  const name = d[0].value;
  if (name.match(/^[a-z](?:_?[a-z0-9]+)*$/) == undefined) return reject;
  return { name };
} %}

constantField -> [A-Z0-9_]:+ {% function(d, _, reject) {
  const name = d[0][0].value;
  if (name.match(/^[A-Z_][A-Z0-9_]*$/) == undefined) return reject;
  return { name, isConstant: true };
} %}

# Constant Values

boolConstantValue -> bool {% function(d) { return { value: d[0] } } %}

numericConstantValue -> number {% function(d) { return { value: d[0] } } %}

stringConstantValue -> (doubleQuotedString | singleQuotedString) {% function(d) { return { value: d[0][0] } } %}

# Default Values

boolDefaultValue -> __ (bool | boolArray) {% function(d) { return { defaultValue: d[1][0] } } %}

numericDefaultValue -> __ (number | numberArray) {% function(d) { return { defaultValue: d[1][0] } } %}

stringDefaultValue -> __ (doubleQuotedString | singleQuotedString) {% function(d) { return { defaultValue: d[1][0] } } %}

boolArray ->
    "[" _ "]" {% function(d) { return [] } %}
  | "[" _ bool (_ "," _ bool):* _ "]" {% extractArray %}

numberArray ->
    "[" _ "]" {% function(d) { return [] } %}
  | "[" _ number (_ "," _ number):* _ "]" {% extractArray %}

# Basic Tokens

bool ->
    ("true" | "True" | "1") {% function(d) { return true } %}
  | ("false" | "False" | "0") {% function(d) { return false } %}

number -> %number {% function(d) { return parseFloat(d[0].value) } %}

doubleQuotedString -> %doubleQuotedString {% function(d) { return JSON.parse(d[0].value) } %}

singleQuotedString -> %singleQuotedString {% function(d) {
  let input = d[0].value;
  // Remove wrapping quotes
  input = input.replace(/^[']|[']$/g, ``);
  // Unescape escaped single quotes
  input = input.replace(/\\'/g, `'`);
  // Escape unescaped double quotes
  input = input.replace(/(?<!\\)"/g, `\\"`);
  // Add wrapping double quotes
  input = `"${input}"`;
  return JSON.parse(input);
} %}

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
