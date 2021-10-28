// This file incorporates work covered by the following copyright and
// permission notice:
//
//   Copyright 2018-2021 Cruise LLC
//
//   This source code is licensed under the Apache License, Version 2.0,
//   found at http://www.apache.org/licenses/LICENSE-2.0
//   You may not use this file except in compliance with the License.

export type RosDefaultValue =
  | string
  | number
  | bigint
  | boolean
  | string[]
  | number[]
  | bigint[]
  | boolean[]
  | undefined;

export type RosMsgField = {
  type: string;
  name: string;
  isComplex?: boolean;

  // For arrays
  isArray?: boolean;
  arrayLength?: number | undefined;

  // For constants
  isConstant?: boolean;
  value?: string | number | bigint | boolean | undefined;
  valueText?: string;

  // Sets a maximum upper bound on string length
  upperBound?: number;
  // Sets a maximum upper bound on array length
  arrayUpperBound?: number;
  // Default value to serialize or deserialize when no source value is present
  defaultValue?: RosDefaultValue;
};

export type RosMsgDefinition = {
  name?: string;
  definitions: RosMsgField[];
};
