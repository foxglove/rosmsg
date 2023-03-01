// This file incorporates work covered by the following copyright and
// permission notice:
//
//   Copyright 2018-2021 Cruise LLC
//
//   This source code is licensed under the Apache License, Version 2.0,
//   found at http://www.apache.org/licenses/LICENSE-2.0
//   You may not use this file except in compliance with the License.

import { Grammar, Parser } from "nearley";

import { buildRos2Type } from "./buildRos2Type";
import ros1Rules from "./ros1.ne";
import ros2idlRules from "./ros2idl.ne";
import { RosMsgField, RosMsgDefinition } from "./types";

const ROS1_GRAMMAR = Grammar.fromCompiled(ros1Rules);
const ROS2IDL_GRAMMAR = Grammar.fromCompiled(ros2idlRules);

export type ParseOptions = {
  /** Parse message definitions as ROS 2. Otherwise, parse as ROS1 */
  ros2?: boolean;
  /** Parse message definitions in the ROS 2 subset of IDL */
  ros2idl?: boolean;
  /**
   * Return the original type names used in the file, without normalizing to
   * fully qualified type names
   */
  skipTypeFixup?: boolean;
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
  if (options.ros2idl) {
    return buildRos2IdlType(messageDefinition, ROS2IDL_GRAMMAR);
  }
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
          : buildType(definitionLines, ROS1_GRAMMAR),
      );
      definitionLines = [];
    } else {
      definitionLines.push({ line });
    }
  });
  types.push(
    options.ros2 === true
      ? buildRos2Type(definitionLines)
      : buildType(definitionLines, ROS1_GRAMMAR),
  );

  // Fix up complex type names
  if (options.skipTypeFixup !== true) {
    fixupTypes(types);
  }

  return types;
}

export function fixupTypes(types: RosMsgDefinition[]): void {
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
}

function buildRos2IdlType(messageDefinition: string, grammar: Grammar): RosMsgDefinition[] {
  const parser = new Parser(grammar);
  parser.feed(messageDefinition);
  const results = parser.finish();

  if (results.length === 0) {
    throw new Error(
      `Could not parse message definition (unexpected end of input): '${messageDefinition}'`,
    );
  }
  const result = results[0] as RosMsgDefinition[];
  return result;
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
