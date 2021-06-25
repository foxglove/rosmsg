# rosmsg

> _ROS1 and ROS2 message definition parser_

## Introduction

[The Robot Operating System (ROS)](https://www.ros.org/) defines a simplified message description language for describing data types. This library parses those message definitions and can round trip them back into a canonical string format suitable for checksum generation. The parsed definitions are useful for serialization or deserialization when paired with other libraries.

This library supports both [ROS1](http://wiki.ros.org/msg) and [ROS2](https://docs.ros.org/en/galactic/Concepts/About-ROS-Interfaces.html) message definitions.

## Usage

```Typescript
const rosmsg = require("@foxglove/rosmsg");

const definitionStr = `# geometry_msgs/Pose
geometry_msgs/Point position
geometry_msgs/Quaternion orientation

===
MSG: geometry_msgs/Point
float64 x
float64 y
float64 z

===
MSG: geometry_msgs/Quaternion
float64 x
float64 y
float64 z
float64 w`;

const messageDefinition = rosmsg.parse(definitionStr);

// rosmsg.stringify(messageDefinition) will return a canonical string, similar
// to _definitionStr_

// print the parsed message definition structure
console.log(JSON.stringify(messageDefinition, null, 2));
```

Prints:

```JSON
[
  {
    "definitions": [
      {
        "type": "geometry_msgs/Point",
        "isArray": false,
        "name": "position",
        "isComplex": true
      },
      {
        "type": "geometry_msgs/Quaternion",
        "isArray": false,
        "name": "orientation",
        "isComplex": true
      }
    ]
  },
  {
    "name": "geometry_msgs/Point",
    "definitions": [
      {
        "type": "float64",
        "isArray": false,
        "name": "x",
        "isComplex": false
      },
      {
        "type": "float64",
        "isArray": false,
        "name": "y",
        "isComplex": false
      },
      {
        "type": "float64",
        "isArray": false,
        "name": "z",
        "isComplex": false
      }
    ]
  },
  {
    "name": "geometry_msgs/Quaternion",
    "definitions": [
      {
        "type": "float64",
        "isArray": false,
        "name": "x",
        "isComplex": false
      },
      {
        "type": "float64",
        "isArray": false,
        "name": "y",
        "isComplex": false
      },
      {
        "type": "float64",
        "isArray": false,
        "name": "z",
        "isComplex": false
      },
      {
        "type": "float64",
        "isArray": false,
        "name": "w",
        "isComplex": false
      }
    ]
  }
]
```

## License

@foxglove/rosmsg is licensed under [Mozilla Public License, v2.0](https://opensource.org/licenses/MPL-2.0).
