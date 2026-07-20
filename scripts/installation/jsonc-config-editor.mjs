import { applyEdits, modify, parse, printParseErrorCode } from "jsonc-parser";

const formattingOptions = {
  insertSpaces: true,
  tabSize: 2,
  eol: "\n"
};

export function parseJSONCObject(configText, configurationName) {
  const source = normalizeSource(configText);
  const errors = [];
  const value = parse(source, errors, { allowTrailingComma: true });
  if (errors.length > 0) {
    const firstError = errors[0];
    throw new Error(
      `Failed: invalid ${configurationName} JSONC configuration at offset ${firstError.offset}: ${printParseErrorCode(firstError.error)}`
    );
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`Failed: ${configurationName} configuration root must be an object`);
  }
  return value;
}

export function upsertJSONCEntry(configText, {
  configurationName,
  containerKey,
  entryKey,
  value
}) {
  const source = normalizeSource(configText);
  const config = parseJSONCObject(source, configurationName);
  assertOptionalObject(config[containerKey], configurationName, containerKey);
  return applyJSONCEdits(source, [containerKey, entryKey], value);
}

export function removeJSONCEntry(configText, {
  configurationName,
  containerKey,
  entryKey
}) {
  const source = normalizeSource(configText);
  const config = parseJSONCObject(source, configurationName);
  assertOptionalObject(config[containerKey], configurationName, containerKey);
  return applyJSONCEdits(source, [containerKey, entryKey], undefined);
}

function assertOptionalObject(value, configurationName, containerKey) {
  if (value !== undefined && (!value || typeof value !== "object" || Array.isArray(value))) {
    throw new Error(`Failed: ${configurationName} ${containerKey} configuration must be an object`);
  }
}

function applyJSONCEdits(source, path, value) {
  return normalizeTrailingNewline(applyEdits(
    source,
    modify(source, path, value, { formattingOptions })
  ));
}

function normalizeSource(configText) {
  return configText.trim() ? configText : "{}\n";
}

function normalizeTrailingNewline(text) {
  return `${text.trimEnd()}\n`;
}
