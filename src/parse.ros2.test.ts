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

import { parse } from "./parse";

describe("parseMessageDefinition", () => {
  it("parses a single field from a single message", () => {
    const types = parse("string name", { ros2: true });
    expect(types).toEqual([
      {
        definitions: [
          {
            arrayLength: undefined,
            isArray: false,
            isComplex: false,
            name: "name",
            type: "string",
          },
        ],
        name: undefined,
      },
    ]);
  });

  it("resolves unqualified names", () => {
    const messageDefinition = `
      Point[] points
      ============
      MSG: geometry_msgs/Point
      float64 x
    `;
    const types = parse(messageDefinition, { ros2: true });
    expect(types).toEqual([
      {
        definitions: [
          {
            isArray: true,
            isComplex: true,
            name: "points",
            type: "geometry_msgs/Point",
          },
        ],
        name: undefined,
      },
      {
        definitions: [
          {
            isArray: false,
            isComplex: false,
            name: "x",
            type: "float64",
          },
        ],
        name: "geometry_msgs/Point",
      },
    ]);
  });

  it("normalizes aliases", () => {
    const types = parse("char x\nbyte y", { ros2: true });
    expect(types).toEqual([
      {
        definitions: [
          {
            isArray: false,
            isComplex: false,
            name: "x",
            type: "uint8",
          },
          {
            isArray: false,
            isComplex: false,
            name: "y",
            type: "int8",
          },
        ],
        name: undefined,
      },
    ]);
  });

  it("ignores comment lines", () => {
    const messageDefinition = `
    # your first name goes here
    string first_name

    # last name here
    ### foo bar baz?
    string last_name
    `;
    const types = parse(messageDefinition, { ros2: true });
    expect(types).toEqual([
      {
        definitions: [
          {
            isArray: false,
            isComplex: false,
            name: "first_name",
            type: "string",
          },
          {
            isArray: false,
            isComplex: false,
            name: "last_name",
            type: "string",
          },
        ],
        name: undefined,
      },
    ]);
  });

  it("parses variable length string array", () => {
    const types = parse("string[] names", { ros2: true });
    expect(types).toEqual([
      {
        definitions: [
          {
            isArray: true,
            isComplex: false,
            name: "names",
            type: "string",
          },
        ],
        name: undefined,
      },
    ]);
  });

  it("parses fixed length string array", () => {
    const types = parse("string[3] names", { ros2: true });
    expect(types).toEqual([
      {
        definitions: [
          {
            arrayLength: 3,
            isArray: true,
            isComplex: false,
            name: "names",
            type: "string",
          },
        ],
        name: undefined,
      },
    ]);
  });

  it("parses nested complex types", () => {
    const messageDefinition = `
    string username
    Account account
    ============
    MSG: custom_type/Account
    string name
    uint16 id
    `;
    const types = parse(messageDefinition, { ros2: true });
    expect(types).toEqual([
      {
        definitions: [
          {
            isArray: false,
            isComplex: false,
            name: "username",
            type: "string",
          },
          {
            isArray: false,
            isComplex: true,
            name: "account",
            type: "custom_type/Account",
          },
        ],
        name: undefined,
      },
      {
        definitions: [
          {
            isArray: false,
            isComplex: false,
            name: "name",
            type: "string",
          },
          {
            isArray: false,
            isComplex: false,
            name: "id",
            type: "uint16",
          },
        ],
        name: "custom_type/Account",
      },
    ]);
  });

  it("returns constants", () => {
    const messageDefinition = `
      uint32 FOO = 55
      int32 BAR=-11 # Comment! # another comment
      float32 BAZ= \t -32.25
      bool SOME_BOOLEAN = 0
      string FOO_STR = 'Foo'    ${""}
      string EXAMPLE="#comments" # are handled properly
    `;
    const types = parse(messageDefinition, { ros2: true });
    expect(types).toEqual([
      {
        definitions: [
          {
            name: "FOO",
            type: "uint32",
            isConstant: true,
            value: 55,
          },
          {
            name: "BAR",
            type: "int32",
            isConstant: true,
            value: -11,
          },
          {
            name: "BAZ",
            type: "float32",
            isConstant: true,
            value: -32.25,
          },
          {
            name: "SOME_BOOLEAN",
            type: "bool",
            isConstant: true,
            value: false,
          },
          {
            name: "FOO_STR",
            type: "string",
            isConstant: true,
            value: "Foo",
          },
          {
            name: "EXAMPLE",
            type: "string",
            isConstant: true,
            value: "#comments",
          },
        ],
        name: undefined,
      },
    ]);
  });

  it("works with python boolean values", () => {
    const messageDefinition = `
      bool ALIVE=True
      bool DEAD=False
    `;
    const types = parse(messageDefinition, { ros2: true });
    expect(types).toEqual([
      {
        definitions: [
          {
            name: "ALIVE",
            type: "bool",
            isConstant: true,
            value: true,
          },
          {
            name: "DEAD",
            type: "bool",
            isConstant: true,
            value: false,
          },
        ],
        name: undefined,
      },
    ]);
  });

  it("parses default values", () => {
    const messageDefinition = `
      int8 a 0
      int8 b -1
      bool c false
      bool d False
      bool e true
      bool f True
      string g "hello"
      string h 'hello'
      string i "'hello'"
      string j '"hello"'
      string k "\\"hello\\""
      string l '\\'hello\\''
    `;
    const types = parse(messageDefinition, { ros2: true });
    expect(types).toEqual([
      {
        definitions: [
          {
            name: "a",
            type: "int8",
            defaultValue: 0,
            isArray: false,
            isComplex: false,
          },
          {
            name: "b",
            type: "int8",
            defaultValue: -1,
            isArray: false,
            isComplex: false,
          },
          {
            name: "c",
            type: "bool",
            defaultValue: false,
            isArray: false,
            isComplex: false,
          },
          {
            name: "d",
            type: "bool",
            defaultValue: false,
            isArray: false,
            isComplex: false,
          },
          {
            name: "e",
            type: "bool",
            defaultValue: true,
            isArray: false,
            isComplex: false,
          },
          {
            name: "f",
            type: "bool",
            defaultValue: true,
            isArray: false,
            isComplex: false,
          },
          {
            name: "g",
            type: "string",
            defaultValue: "hello",
            isArray: false,
            isComplex: false,
          },
          {
            name: "h",
            type: "string",
            defaultValue: "hello",
            isArray: false,
            isComplex: false,
          },
          {
            name: "i",
            type: "string",
            defaultValue: `'hello'`,
            isArray: false,
            isComplex: false,
          },
          {
            name: "j",
            type: "string",
            defaultValue: `"hello"`,
            isArray: false,
            isComplex: false,
          },
          {
            name: "k",
            type: "string",
            defaultValue: `"hello"`,
            isArray: false,
            isComplex: false,
          },
          {
            name: "l",
            type: "string",
            defaultValue: "'hello'",
            isArray: false,
            isComplex: false,
          },
        ],
        name: undefined,
      },
    ]);
  });
});
