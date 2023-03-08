// This file incorporates work covered by the following copyright and
// permission notice:
//
//   Copyright 2018-2021 Cruise LLC
//
//   This source code is licensed under the Apache License, Version 2.0,
//   found at http://www.apache.org/licenses/LICENSE-2.0
//   You may not use this file except in compliance with the License.

import {
  ConstantValue,
  MessageDefinition,
  MessageDefinitionField,
} from "@foxglove/message-definition";
import { Grammar, Parser } from "nearley";

import { buildRos2Type } from "./buildRos2Type";
import ros1Rules from "./ros1.ne";
import ros2idlRules from "./ros2idl.ne";

const ROS1_GRAMMAR = Grammar.fromCompiled(ros1Rules);
const ROS2IDL_GRAMMAR = Grammar.fromCompiled(ros2idlRules);

export type ParseOptions = {
  /** Parse message definitions as ROS 2. Otherwise, parse as ROS1 */
  ros2?: boolean;
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
export function parse(messageDefinition: string, options: ParseOptions = {}): MessageDefinition[] {
  // read all the lines and remove empties
  const allLines = messageDefinition
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line);

  let definitionLines: { line: string }[] = [];
  const types: MessageDefinition[] = [];
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

export function fixupTypes(types: MessageDefinition[]): void {
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

/**
 *
 * @param messageDefinition - ros2idl decoded message definition string
 * @returns - parsed message definition
 */
export function parseRos2idl(messageDefinition: string): MessageDefinition[] {
  return buildRos2idlType(messageDefinition, ROS2IDL_GRAMMAR);
}

type ConstantVariableValue = {
  usesConstant: boolean;
  name: string;
};

type RawIdlDefinition = {
  definitions: (RawIdlDefinition | RawIdlFieldDefinition)[];
  name: string;
  definitionType: "module" | "struct";
};

type RawIdlFieldDefinition = Partial<MessageDefinitionField> & {
  definitionType?: "typedef";
  value?: ConstantValue | ConstantVariableValue;
};

function buildRos2idlType(messageDefinition: string, grammar: Grammar): MessageDefinition[] {
  const parser = new Parser(grammar);
  parser.feed(messageDefinition);
  const results = parser.finish();

  if (results.length === 0) {
    throw new Error(
      `Could not parse message definition (unexpected end of input): '${messageDefinition}'`,
    );
  }
  const result = results[0] as RawIdlDefinition[];
  const processedResult = postProcessIdlDefinitions(result);
  for (const { definitions } of processedResult) {
    for (const definition of definitions) {
      definition.type = normalizeType(definition.type);
    }
  }

  return processedResult;
}

function traverseIdl(
  path: (RawIdlDefinition | RawIdlFieldDefinition)[],
  processNode: (path: (RawIdlDefinition | RawIdlFieldDefinition)[]) => void,
) {
  const currNode = path[path.length - 1]!;
  const children: (RawIdlDefinition | RawIdlFieldDefinition)[] = (currNode as RawIdlDefinition)
    .definitions;
  if (children) {
    children.forEach((n) => traverseIdl([...path, n], processNode));
  }
  processNode(path);
}

function postProcessIdlDefinitions(definitions: RawIdlDefinition[]): MessageDefinition[] {
  const finalDefs: MessageDefinition[] = [];
  // Need to update the names of modules and structs to be in their respective namespaces
  for (const definition of definitions) {
    const typedefMap = new Map<string, Partial<RawIdlFieldDefinition>>();
    const constantValueMap = new Map<string, ConstantValue>();
    // build constant and typedef maps
    traverseIdl([definition], (path) => {
      const node = path[path.length - 1] as RawIdlFieldDefinition;
      if (node.definitionType === "typedef") {
        // typedefs must have a name
        const { definitionType: _definitionType, name: _name, ...partialDef } = node;
        typedefMap.set(node.name!, partialDef);
      } else if (node.isConstant === true) {
        constantValueMap.set(node.name!, node.value);
      }
    });

    // modify ast nodes in-place to replace typedefs and constants
    // also fix up names to use ros package resource names
    traverseIdl([definition], (path) => {
      const node = path[path.length - 1] as RawIdlFieldDefinition;

      const nodeKeys = Object.keys(node) as (keyof RawIdlFieldDefinition)[];
      // need to iterate through keys because this can occur on arrayLength, upperBound, arrayUpperBound, value, defaultValue
      for (const key of nodeKeys) {
        if ((node[key] as ConstantVariableValue)?.usesConstant === true) {
          const constantName = (node[key] as ConstantVariableValue).name;
          if (constantValueMap.has(constantName)) {
            (node[key] as ConstantValue) = constantValueMap.get(constantName);
          } else {
            throw new Error(
              `Could not find constant ${constantName} for field ${node.name} in ${definition.name}`,
            );
          }
        }
      }
      // replace field definition with corresponding typedef aliased definition
      if (node.type && typedefMap.has(node.type!)) {
        Object.assign(node, { ...typedefMap.get(node.type!), name: node.name });
      }
      if (node.type !== undefined) {
        node.type = node.type.replace(/::/g, "/");
      }
    });

    const flattened = flattenIdlNamespaces(definition);
    finalDefs.push(...flattened);
  }

  return finalDefs;
}

function flattenIdlNamespaces(definition: RawIdlDefinition): MessageDefinition[] {
  const flattened: MessageDefinition[] = [];

  traverseIdl([definition], (path) => {
    const node = path[path.length - 1] as RawIdlDefinition;
    if (node.definitionType === "module") {
      let moduleDefs = node.definitions.filter((d) => d.definitionType !== "typedef");
      // only add modules if all fields are constants (complex leaf)
      if (moduleDefs.every((child) => (child as RawIdlFieldDefinition).isConstant)) {
        flattened.push({
          name: path.map((n) => n.name).join("/"),
          definitions: moduleDefs as MessageDefinitionField[],
        });
      }
    } else if (node.definitionType === "struct") {
      // all structs are leaf nodes to be added
      flattened.push({
        name: path.map((n) => n.name).join("/"),
        definitions: node.definitions as MessageDefinitionField[],
      });
    }
  });

  return flattened;
}

function buildType(lines: { line: string }[], grammar: Grammar): MessageDefinition {
  const definitions: MessageDefinitionField[] = [];
  let complexTypeName: string | undefined;
  lines.forEach(({ line }) => {
    if (line.startsWith("MSG:")) {
      const [_, name] = simpleTokenization(line);
      complexTypeName = name?.trim();
      return;
    }

    const parser = new Parser(grammar);
    parser.feed(line);
    const results = parser.finish() as MessageDefinitionField[];
    if (results.length === 0) {
      throw new Error(`Could not parse line: '${line}'`);
    } else if (results.length > 1) {
      throw new Error(`Ambiguous line: '${line}'`);
    }
    const result = results[0];
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

function findTypeByName(types: MessageDefinition[], name: string): MessageDefinition {
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
