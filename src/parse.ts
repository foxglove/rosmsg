// This Source Code Form is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/
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
import ros2Rules from "./ros2.ne";
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
  const grammar = Grammar.fromCompiled(options.ros2 === true ? ros2Rules : ros1Rules);

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
      types.push(buildType(definitionLines, grammar));
      definitionLines = [];
    } else {
      definitionLines.push({ line });
    }
  });
  types.push(buildType(definitionLines, grammar));

  // Fix up complex type names
  types.forEach(({ definitions }) => {
    definitions.forEach((definition) => {
      if (definition.isComplex) {
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
    const result = parser.results[0] as RosMsgField;
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
