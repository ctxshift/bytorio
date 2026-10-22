import * as schema from "./constants.js";

const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true });
const eventMask =
  schema.TEXT_INPUT_CHANGED | schema.TEXT_INPUT_SUBMITTED | schema.TEXT_INPUT_CANCELLED;
const terminalMask = schema.TEXT_INPUT_SUBMITTED | schema.TEXT_INPUT_CANCELLED;

export const unavailableTextImports = Object.freeze({
  text_configure: () => 0,
  text_read: () => 0,
});

function validSelection(bytes, start, end) {
  const boundary = (offset) => offset === bytes.length || (bytes[offset] & 0xc0) !== 0x80;
  return (
    Number.isInteger(start) &&
    Number.isInteger(end) &&
    start >= 0 &&
    start <= end &&
    end <= bytes.length &&
    boundary(start) &&
    boundary(end)
  );
}

function validText(value) {
  if (typeof value !== "string" || !value.isWellFormed()) {
    return false;
  }
  for (const character of value) {
    const code = character.codePointAt(0);
    if (code < 32 || code === 127) {
      return false;
    }
  }
  return true;
}

// The worker owns the current field and a bounded pending event snapshot. DOM
// messages cannot replace another configuration's identity or generation.
export function createTextInputSession(getGame, { onConfigure = () => {} } = {}) {
  let current = null;
  let revision = 0;
  let sequence = 0;
  let readAllowed = true;
  const advance = () => {
    revision = (revision + 1) >>> 0 || 1;
  };
  const snapshot = () => (current ? { ...current } : null);
  function memory(pointer, length) {
    pointer >>>= 0;
    length >>>= 0;
    const buffer = getGame()?.memory?.buffer;
    if (
      !buffer ||
      length > schema.TEXT_INPUT_HEADER_BYTES + schema.TEXT_INPUT_MAX_BYTES ||
      pointer + length > buffer.byteLength
    ) {
      return null;
    }
    return new Uint8Array(buffer, pointer, length);
  }
  function configure(pointer, length) {
    const source = memory(pointer, length);
    if (!source || source.length < schema.TEXT_INPUT_HEADER_BYTES) {
      return 0;
    }
    const header = new DataView(source.buffer, source.byteOffset, source.byteLength);
    const word = (field) => header.getUint32(field, true);
    if (word(schema.TEXT_INPUT_FIELD_VERSION) !== schema.TEXT_INPUT_VERSION) {
      return 0;
    }
    const id = word(schema.TEXT_INPUT_FIELD_ID);
    if (id === 0) {
      if (
        source.length !== schema.TEXT_INPUT_HEADER_BYTES ||
        source.subarray(8).some((byte) => byte !== 0)
      ) {
        return 0;
      }
      advance();
      sequence = 0;
      current = null;
      onConfigure(null);
      return 1;
    }
    const maximum = word(schema.TEXT_INPUT_FIELD_MAX_BYTES);
    const size = word(schema.TEXT_INPUT_FIELD_LENGTH);
    const start = word(schema.TEXT_INPUT_FIELD_START);
    const end = word(schema.TEXT_INPUT_FIELD_END);
    const x = header.getInt32(schema.TEXT_INPUT_FIELD_X, true);
    const y = header.getInt32(schema.TEXT_INPUT_FIELD_Y, true);
    const width = header.getInt32(schema.TEXT_INPUT_FIELD_WIDTH, true);
    const height = header.getInt32(schema.TEXT_INPUT_FIELD_HEIGHT, true);
    if (
      word(schema.TEXT_INPUT_FIELD_REVISION) !== 0 ||
      word(schema.TEXT_INPUT_FIELD_FLAGS) !== schema.TEXT_INPUT_ACTIVE ||
      maximum < 1 ||
      maximum > schema.TEXT_INPUT_MAX_BYTES ||
      size > maximum ||
      source.length !== schema.TEXT_INPUT_HEADER_BYTES + size ||
      x < schema.COORDINATE_MIN ||
      x > schema.COORDINATE_MAX ||
      y < schema.COORDINATE_MIN ||
      y > schema.COORDINATE_MAX ||
      width < 1 ||
      width > schema.COORDINATE_MAX ||
      height < 1 ||
      height > schema.COORDINATE_MAX
    ) {
      return 0;
    }
    const bytes = source.subarray(schema.TEXT_INPUT_HEADER_BYTES);
    if (!validSelection(bytes, start, end)) {
      return 0;
    }
    let value;
    try {
      value = decoder.decode(bytes);
    } catch {
      return 0;
    }
    if (!validText(value)) {
      return 0;
    }
    advance();
    sequence = 0;
    current = {
      id,
      revision,
      flags: schema.TEXT_INPUT_ACTIVE,
      maxBytes: maximum,
      value,
      start,
      end,
      x,
      y,
      width,
      height,
    };
    onConfigure(snapshot());
    return 1;
  }
  function read(pointer, capacity) {
    if (!current || !readAllowed) {
      return 0;
    }
    const bytes = encoder.encode(current.value);
    const size = schema.TEXT_INPUT_HEADER_BYTES + bytes.length;
    if (
      capacity >>> 0 < size ||
      capacity >>> 0 > schema.TEXT_INPUT_HEADER_BYTES + schema.TEXT_INPUT_MAX_BYTES
    ) {
      return 0;
    }
    const capacityBytes = memory(pointer, capacity);
    if (!capacityBytes) {
      return 0;
    }
    const destination = capacityBytes.subarray(0, size);
    const header = new DataView(destination.buffer, destination.byteOffset, destination.byteLength);
    destination.fill(0);
    for (const [field, value] of [
      [schema.TEXT_INPUT_FIELD_VERSION, schema.TEXT_INPUT_VERSION],
      [schema.TEXT_INPUT_FIELD_ID, current.id],
      [schema.TEXT_INPUT_FIELD_REVISION, current.revision],
      [schema.TEXT_INPUT_FIELD_FLAGS, current.flags],
      [schema.TEXT_INPUT_FIELD_MAX_BYTES, current.maxBytes],
      [schema.TEXT_INPUT_FIELD_LENGTH, bytes.length],
      [schema.TEXT_INPUT_FIELD_START, current.start],
      [schema.TEXT_INPUT_FIELD_END, current.end],
      [schema.TEXT_INPUT_FIELD_X, current.x],
      [schema.TEXT_INPUT_FIELD_Y, current.y],
      [schema.TEXT_INPUT_FIELD_WIDTH, current.width],
      [schema.TEXT_INPUT_FIELD_HEIGHT, current.height],
    ]) {
      header.setUint32(field, value >>> 0, true);
    }
    destination.set(bytes, schema.TEXT_INPUT_HEADER_BYTES);
    current.flags &= ~eventMask;
    readAllowed = false;
    return size;
  }
  return {
    imports: { text_configure: configure, text_read: read },
    beginTick: () => {
      readAllowed = true;
    },
    snapshot,
    accept(update) {
      if (
        !current ||
        !(current.flags & schema.TEXT_INPUT_ACTIVE) ||
        !update ||
        update.id !== current.id ||
        update.revision !== current.revision ||
        !Number.isInteger(update.sequence) ||
        update.sequence <= sequence ||
        update.sequence > 0xffffffff ||
        !Number.isInteger(update.flags) ||
        update.flags <= 0 ||
        update.flags > eventMask ||
        (update.flags & ~eventMask) !== 0 ||
        (update.flags & terminalMask) === terminalMask ||
        !validText(update.value)
      ) {
        return false;
      }
      const bytes = encoder.encode(update.value);
      if (bytes.length > current.maxBytes || !validSelection(bytes, update.start, update.end)) {
        return false;
      }
      sequence = update.sequence;
      Object.assign(current, { value: update.value, start: update.start, end: update.end });
      current.flags |= update.flags;
      if (update.flags & terminalMask) {
        current.flags &= ~schema.TEXT_INPUT_ACTIVE;
        onConfigure(null);
      }
      return true;
    },
    close() {
      advance();
      current = null;
      sequence = 0;
      onConfigure(null);
    },
  };
}
