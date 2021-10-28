// This file incorporates work covered by the following copyright and
// permission notice:
//
//   Copyright 2018-2021 Cruise LLC
//
//   This source code is licensed under the Apache License, Version 2.0,
//   found at http://www.apache.org/licenses/LICENSE-2.0
//   You may not use this file except in compliance with the License.

import { Grammar, Parser } from "nearley";

import ros1Rules from "./ros1.ne";
import { RosMsgField, RosMsgDefinition } from "./types";

export type ParseOptions = {
  ros2?: boolean;
};

// Given a raw message definition string, parse it into an object representation.
// Example return value:
// [{
//   name: undefined,
//   definitions: [
//     {
//       arrayLength: undefined,
//       isArray: false,
//       isComplex: false,
//       name: "name",
//       type: "string",
//       defaultValue: undefined
//     }, ...
//   ],
// }, ... ]
//
// See unit tests for more examples.
export function parse(messageDefinition: string, options: ParseOptions = {}): RosMsgDefinition[] {
  const grammar = Grammar.fromCompiled(ros1Rules);

  // read all the lines and remove empties
  const allLines = messageDefinition
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line);

  let definitionLines: { line: string }[] = [];
  const types: RosMsgDefinition[] = [];
  // group lines into individual definitions
  allLines.forEach((line) => {
    // ignore comment lines
    if (line.startsWith("#")) {
      return;
    }

    // definitions are split by equal signs
    if (line.startsWith("==")) {
      types.push(
        options.ros2 === true
          ? buildRos2Type(definitionLines)
          : buildType(definitionLines, grammar),
      );
      definitionLines = [];
    } else {
      definitionLines.push({ line });
    }
  });
  types.push(
    options.ros2 === true ? buildRos2Type(definitionLines) : buildType(definitionLines, grammar),
  );

  // Fix up complex type names
  types.forEach(({ definitions }) => {
    definitions.forEach((definition) => {
      if (definition.isComplex === true) {
        const foundName = findTypeByName(types, definition.type).name;
        if (foundName == undefined) {
          throw new Error(`Missing type definition for ${definition.type}`);
        }
        definition.type = foundName;
      }
    });
  });

  return types;
}

function buildType(lines: { line: string }[], grammar: Grammar): RosMsgDefinition {
  const definitions: RosMsgField[] = [];
  let complexTypeName: string | undefined;
  lines.forEach(({ line }) => {
    if (line.startsWith("MSG:")) {
      const [_, name] = simpleTokenization(line);
      complexTypeName = name?.trim();
      return;
    }

    const parser = new Parser(grammar);
    parser.feed(line);
    const results = parser.finish();
    if (results.length === 0) {
      throw new Error(`Could not parse line: '${line}'`);
    } else if (results.length > 1) {
      throw new Error(`Ambiguous line: '${line}'`);
    }
    const result = results[0] as RosMsgField;
    if (result != undefined) {
      result.type = normalizeType(result.type);
      definitions.push(result);
    }
  });
  return { name: complexTypeName, definitions };
}

function parseBigIntLiteral(str: string, min: bigint, max: bigint) {
  const value = BigInt(str);
  if (value < min || value > max) {
    throw new Error(`Number ${str} out of range [${min}, ${max}]`);
  }
  return value;
}
function parseNumberLiteral(str: string, min: number, max: number): number {
  const value = parseInt(str);
  if (value < min || value > max) {
    throw new Error(`Number ${str} out of range [${min}, ${max}]`);
  }
  return value;
}

function parseArrayLiteral(
  type: string,
  rawStr: string,
): boolean[] | bigint[] | number[] | string[] {
  if (!rawStr.startsWith("[") || !rawStr.endsWith("]")) {
    throw new Error("Array must start with [ and end with ]");
  }
  const str = rawStr.substring(1, rawStr.length - 1);
  if (type === "string" || type === "wstring") {
    const unquotedStringWithoutCommaPattern =
      /(?:[^\\,]|\\['"abfnrtv\\]|\\[0-7]{1,3}|\\x[a-fA-F0-9]{2}|\\u[a-fA-F0-9]{4}|\\U[a-fA-F0-9]{8})*/y;
    const singleQuotedStringPattern =
      /'(?:[^\\']|\\['"abfnrtv\\]|\\[0-7]{1,3}|\\x[a-fA-F0-9]{2}|\\u[a-fA-F0-9]{4}|\\U[a-fA-F0-9]{8})*'/y;
    const doubleQuotedStringPattern =
      /"(?:[^\\"]|\\['"abfnrtv\\]|\\[0-7]{1,3}|\\x[a-fA-F0-9]{2}|\\u[a-fA-F0-9]{4}|\\U[a-fA-F0-9]{8})*"/y;
    const commaOrEndPattern = /\s*(,)\s*|\s*$/y;

    const results: string[] = [];
    let offset = 0;
    while (offset < str.length) {
      if (str[offset] === ",") {
        throw new Error("Expected array element before comma");
      }
      let match;
      unquotedStringWithoutCommaPattern.lastIndex = offset;
      singleQuotedStringPattern.lastIndex = offset;
      doubleQuotedStringPattern.lastIndex = offset;
      if ((match = doubleQuotedStringPattern.exec(str))) {
        results.push(parseStringLiteral(match[0]!));
        offset = doubleQuotedStringPattern.lastIndex;
      } else if ((match = singleQuotedStringPattern.exec(str))) {
        results.push(parseStringLiteral(match[0]!));
        offset = singleQuotedStringPattern.lastIndex;
      } else if ((match = unquotedStringWithoutCommaPattern.exec(str))) {
        results.push(parseStringLiteral(match[0]!));
        offset = unquotedStringWithoutCommaPattern.lastIndex;
      }

      commaOrEndPattern.lastIndex = offset;
      match = commaOrEndPattern.exec(str);
      if (!match) {
        throw new Error("Expected comma or end of array");
      }
      if (!match[1]) {
        break;
      }
      offset = commaOrEndPattern.lastIndex;
    }
    return results;
  }
  return str.split(",").map((part) => parsePrimitiveLiteral(type, part.trim())) as
    | boolean[]
    | bigint[]
    | number[]
    | string[];
}
function parseStringLiteral(maybeQuotedStr: string): string {
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
    !new RegExp(
      String.raw`^(?:[^\\${quoteThatMustBeEscaped}]|\\['"abfnrtv\\]|\\[0-7]{1,3}|\\x[a-fA-F0-9]{2}|\\u[a-fA-F0-9]{4}|\\U[a-fA-F0-9]{8})*$`,
    ).test(str) == undefined
  ) {
    throw new Error(`Invalid string literal: ${str}`);
  }
  return str.replace(
    /\\(['"abfnrtv\\])|\\([0-7]{1,3})|\\x([a-fA-F0-9]{2})|\\u([a-fA-F0-9]{4})|\\U([a-fA-F0-9]{8})/g,
    (_match, char, oct, hex2, hex4, hex8) => {
      if (char != undefined) {
        return {
          "'": "'",
          '"': '"',
          a: "a",
          b: "\b",
          f: "\f",
          n: "\n",
          r: "\r",
          t: "\t",
          v: "\v",
          "\\": "\\",
        }[char as string]!;
      } else if (oct != undefined) {
        return String.fromCodePoint(parseInt(oct, 8));
      } else if (hex2 != undefined || hex4 != undefined || hex8 != undefined) {
        return String.fromCodePoint(parseInt(hex2 ?? hex4 ?? hex8, 16));
      } else {
        throw new Error("Expected exactly one matched group");
      }
    },
  );
}
function parsePrimitiveLiteral(type: string, str: string): boolean | number | bigint | string {
  switch (type) {
    case "bool":
      if (["true", "True", "1"].includes(str)) {
        return true;
      } else if (["false", "False", "0"].includes(str)) {
        return false;
      }
      break;

    case "float32":
    case "float64": {
      const value = parseFloat(str);
      if (!Number.isNaN(value)) {
        return value;
      }
      break;
    }
    case "int8":
      return parseNumberLiteral(str, ~0x7f, 0x7f);
    case "uint8":
      return parseNumberLiteral(str, 0, 0xff);
    case "int16":
      return parseNumberLiteral(str, ~0x7fff, 0x7fff);
    case "uint16":
      return parseNumberLiteral(str, 0, 0xffff);
    case "int32":
      return parseNumberLiteral(str, ~0x7fffffff, 0x7fffffff);
    case "uint32":
      return parseNumberLiteral(str, 0, 0xffffffff);
    case "int64":
      return parseBigIntLiteral(str, ~0x7fffffffffffffffn, 0x7fffffffffffffffn);
    case "uint64":
      return parseBigIntLiteral(str, 0n, 0xffffffffffffffffn);
    case "string":
    case "wstring":
      return parseStringLiteral(str);
  }
  throw new Error(`Invalid literal of type ${type}: ${str}`);
}

function buildRos2Type(lines: { line: string }[]): RosMsgDefinition {
  const definitions: RosMsgField[] = [];
  let complexTypeName: string | undefined;
  for (const { line } of lines) {
    let match;
    if (line.startsWith("#")) {
      continue;
    } else if ((match = /^MSG: ([^ ]+)\s*(?:#.+)?$/.exec(line))) {
      complexTypeName = match[1];
      continue;
    } else if (
      (match =
        /^([a-zA-Z0-9_/]+)(?:<=(\d+))?(?:(\[\])|\[(\d+)\]|\[<=(\d+)\])?\s+([a-zA-Z0-9_]+)(?:(?:\s*=\s*('(?:\\.|[^'])*'|"(?:\\.|[^"])*"|[^#]*))?(?:\s*#.*)?|\s+([^=#].*))?$/.exec(
          line,
        ))
    ) {
      const [
        ,
        rawType,
        stringBound,
        unboundedArray,
        arrayLength,
        arrayBound,
        name,
        constantValue,
        defaultValue,
      ] = match;
      let type = normalizeType(rawType!);
      switch (type) {
        case "builtin_interfaces/Time":
        case "builtin_interfaces/msg/Time":
          type = "time";
          break;
        case "builtin_interfaces/Duration":
        case "builtin_interfaces/msg/Duration":
          type = "duration";
          break;
      }
      if (stringBound != undefined && type !== "string" && type !== "wstring") {
        throw new Error(`Invalid string bound for type ${type}`);
      }
      if (constantValue != undefined) {
        console.log("check const name", name);
        if (!/^[A-Z](?:_?[A-Z0-9]+)*$/.test(name!)) {
          throw new Error(`Invalid constant name: ${name!}`);
        }
      } else {
        if (!/^[a-z](?:_?[a-z0-9]+)*$/.test(name!)) {
          throw new Error(`Invalid field name: ${name!}`);
        }
      }
      const isComplex = ![
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
      ].includes(type);
      const isArray =
        unboundedArray != undefined || arrayLength != undefined || arrayBound != undefined;
      definitions.push({
        name: name!,
        type,
        isComplex: constantValue != undefined ? isComplex || undefined : isComplex,
        isConstant: constantValue != undefined || undefined,
        isArray: constantValue != undefined ? isArray || undefined : isArray,
        arrayLength: arrayLength != undefined ? parseInt(arrayLength) : undefined,
        arrayUpperBound: arrayBound != undefined ? parseInt(arrayBound) : undefined,
        upperBound: stringBound != undefined ? parseInt(stringBound) : undefined,
        defaultValue:
          defaultValue != undefined
            ? isArray
              ? parseArrayLiteral(type, defaultValue.trim())
              : parsePrimitiveLiteral(type, defaultValue.trim())
            : undefined,
        value:
          constantValue != undefined
            ? parsePrimitiveLiteral(type, constantValue.trim())
            : undefined,
        valueText: constantValue?.trim(),
      });
    } else {
      throw new Error(`Could not parse line: '${line}'`);
    }
  }
  return { name: complexTypeName, definitions };
}

function simpleTokenization(line: string): string[] {
  return line
    .replace(/#.*/gi, "")
    .split(" ")
    .filter((word) => word);
}

function findTypeByName(types: RosMsgDefinition[], name: string): RosMsgDefinition {
  const matches = types.filter((type) => {
    const typeName = type.name ?? "";
    // if the search is empty, return unnamed types
    if (name.length === 0) {
      return typeName.length === 0;
    }
    // return if the search is in the type name
    // or matches exactly if a fully-qualified name match is passed to us
    const nameEnd = name.includes("/") ? name : `/${name}`;
    return typeName.endsWith(nameEnd);
  });
  if (matches[0] == undefined) {
    throw new Error(
      `Expected 1 top level type definition for '${name}' but found ${matches.length}`,
    );
  }
  return matches[0];
}

function normalizeType(type: string): string {
  // Normalize deprecated aliases
  if (type === "char") {
    return "uint8";
  } else if (type === "byte") {
    return "int8";
  }
  return type;
}
