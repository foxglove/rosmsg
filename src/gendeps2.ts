import { parse } from "./parse";
import { readFile, readdir } from "fs/promises";
import { join, sep } from "path";

async function main() {
  if (process.argv.length !== 4) {
    console.error("Usage: gendeps <msgdefs-dir> <msg-file>");
    process.exit(1);
  }
  const msgdefsPath = process.argv[2]!;
  const msgFile = process.argv[3]!;
  const msgDefinitionString = await readFile(msgFile, { encoding: "utf8" });
  const currentPackage = getPackagePath(msgdefsPath, msgFile);
  const loadedTypes = new Set<string>();

  // parse just the unique set of type names from the .msg file (in order seen, depth first)
  const complexTypes: string[] = [];
  const msgDefinitions = parse(msgDefinitionString, { ros2: true, skipTypeFixup: true });
  for (const msgdef of msgDefinitions) {
    for (const definition of msgdef.definitions) {
      if (definition.isComplex === true && !complexTypes.includes(definition.type)) {
        complexTypes.push(definition.type);
      }
    }
  }

  console.log(msgDefinitionString);
  while (complexTypes.length > 0) {
    const typeName = complexTypes.shift()!;
    const res = await loadDefinitionForType(typeName, msgdefsPath, currentPackage);
    if (!res) {
      throw new Error(`Failed to load definition for type ${typeName}`);
    }
    const [curTypeName, curMsgDefinitionString] = res;
    loadedTypes.add(curTypeName);
    console.log("================================================================================");
    console.log(`MSG: ${curTypeName}`);
    console.log(curMsgDefinitionString);

    const curMsgDefinitions = parse(curMsgDefinitionString, { ros2: true, skipTypeFixup: true });
    for (const msgdef of curMsgDefinitions) {
      for (const definition of msgdef.definitions) {
        if (
          definition.isComplex === true &&
          !complexTypes.includes(definition.type) &&
          !loadedTypes.has(definition.type)
        ) {
          complexTypes.push(definition.type);
        }
      }
    }
  }

  // for each type name, find the .msg file in the msgdef root directory
  // concatenate the .msg file contents to the output
}

function getPackagePath(msgdefsPath: string, msgFile: string): string {
  const pathParts = msgdefsPath.split(sep);
  const msgFileParts = msgFile.split(sep);

  // Remove pathParts from msgFileParts
  for (const pathPart of pathParts) {
    if (pathPart !== msgFileParts[0]) {
      console.log(`${pathPart} !== ${msgFileParts[0]}`);
      throw new Error(`<msg-file> "${msgFile}" must be under <msgdefs-dir> "${msgdefsPath}"`);
    }
    msgFileParts.shift();
  }

  return msgFileParts[0]!;
}

async function loadDefinitionForType(
  typeName: string,
  rootPath: string,
  currentPackage: string,
): Promise<[string, string] | undefined> {
  if (typeName.includes("/")) {
    // This is a fully qualified type name. Load the definition from the root path
    const parts = typeName.split("/");
    if (parts.length < 2) {
      throw new Error(`Invalid type name: ${typeName}`);
    }
    const packageName = parts[0]!;
    const typeBaseName = parts[parts.length - 1]!;
    const filename = `${typeBaseName}.msg`;
    const contents = await readFileFromPackage(filename, join(rootPath, packageName));
    return contents != undefined ? [typeName, contents] : undefined;
  }

  // This is a relative type name. Load the definition from the relative path
  const filename = `${typeName}.msg`;
  const fullTypeName = `${currentPackage}/${typeName}`;
  const contents = await readFileFromPackage(filename, join(rootPath, currentPackage));
  return contents != undefined ? [fullTypeName, contents] : undefined;
}

// Recursively search inside a directory for a file with a given name
async function readFileFromPackage(
  filename: string,
  packagePath: string,
): Promise<string | undefined> {
  // console.log(`looking for ${filename} in ${packagePath}`);
  const files = await readdir(packagePath, { withFileTypes: true });
  for (const file of files) {
    if (file.isDirectory()) {
      const contents = await readFileFromPackage(filename, join(packagePath, file.name));
      if (contents) {
        return contents;
      }
    } else if (file.isFile() && file.name === filename) {
      return await readFile(join(packagePath, file.name), { encoding: "utf8" });
    }
  }
  return undefined;
}

void main();
