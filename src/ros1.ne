@{%
const moo = require("moo");
const lexer = moo.compile({
  space: {match: /\s+/, lineBreaks: true},
  number: /-?(?:[0-9]|[1-9][0-9]+)(?:\.[0-9]+)?(?:[eE][-+]?[0-9]+)?\b/,
  comment: /#[^\n]*/,
  '[': '[',
  ']': ']',
  assignment: /=[^\n]+/,
  boolType: 'bool',
  numericType: /byte|char|float32|float64|int8|uint8|int16|uint16|int32|uint32|int64|uint64/,
  stringType: /string/,
  timeType: /time|duration/,
  true: /[Tt]rue/,
  false: /[Ff]alse/,
  fieldOrCustomType: /[a-zA-Z_]+(?:\/?[a-zA-Z0-9_]+)?/,
});
%}

@lexer lexer

main ->
    _ boolType arrayType __ field _ comment:? simple {% function(d) { return extend(d) } %}
  | _ numericType arrayType __ field _ comment:? simple {% function(d) { return extend(d) } %}
  | _ stringType arrayType __ field _ comment:? simple {% function(d) { return extend(d) } %}
  | _ timeType arrayType __ field _ comment:? simple {% function(d) { return extend(d) } %}
  | _ customType arrayType __ field _ comment:? complex {% function(d) { return extend(d) } %}
  | _ boolType __ constantField _ boolConstantValue _ comment:? {% function(d) { return extend(d) } %}
  | _ numericType __ constantField _ numericConstantValue _ comment:? {% function(d) { return extend(d) } %}
  | _ stringType __ constantField _ stringConstantValue _ comment:? {% function(d) { return extend(d) } %}
  | comment {% function(d) { return null } %}
  | blankLine {% function(d) { return null } %}

# Types

boolType -> %boolType {% function(d) { return { type: d[0].value } } %}

numericType -> %numericType {% function(d) { return { type: d[0].value } } %}

stringType -> %stringType {% function(d) { return { type: d[0].value } } %}

timeType -> %timeType {% function(d) { return { type: d[0].value } } %}

customType -> %fieldOrCustomType {% function(d) { return { type: d[0].value } } %}

arrayType ->
    "[" _ "]" {% function(d) { return { isArray: true } } %}
  | "[" _ number _ "]" {% function(d) { return { isArray: true, arrayLength: d[2] } } %}
  | _ {% function(d) { return { isArray: false } } %}

# Fields

field -> %fieldOrCustomType {% function(d, _, reject) {
  const name = d[0].value;
  if (name.match(/^[a-zA-Z](?:_?[a-zA-Z0-9]+)*$/) == undefined) return reject;
  return { name };
} %}

constantField -> [a-zA-Z0-9_]:+ {% function(d, _, reject) {
  const name = d[0][0].value;
  if (name.match(/^[a-zA-Z_][a-zA-Z0-9_]*$/) == undefined) return reject;
  return { name, isConstant: true };
} %}

# Constant Values

boolConstantValue -> assignment {% function(d, _, reject) {
  const value = d[0];
  if (value.toLowerCase() === "true" || value.toLowerCase() === "1") return { value: true };
  if (value.toLowerCase() === "false" || value.toLowerCase() === "0") return { value: false };
  return reject;
} %}

numericConstantValue -> assignment {% function(d, _, reject) {
  const value = parseFloat(d[0]);
  return !isNaN(value) ? { value } : reject;
} %}

stringConstantValue -> assignment {% function(d) { return { value: d[0] } } %}

# Basic Tokens

bool ->
    ("true" | "True" | "1") {% function(d) { return true } %}
  | ("false" | "False" | "0") {% function(d) { return false } %}

number -> %number {% function(d) { return parseFloat(d[0].value) } %}

# =...
assignment -> %assignment {% function(d) { return d[0].value.substr(1).trim() } %}

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
%}
