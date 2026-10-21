// Only the Luau bridge lives here; resource validation/storage belongs to Odin.
#include "resource_transport.h"
#include "console_constants.h"
#include "resource_schema.h"
#include <cmath>
#include <cstring>
#include <emscripten/emscripten.h>
#include <lualib.h>
extern "C" std::uint32_t game_profile();

namespace resource_transport {
using namespace resource_schema;
using namespace console_constants;
constexpr unsigned payload_base = headerBytes + maxCommands * commandBytes;
unsigned char packet[payload_base + maxPayload];
unsigned configured_session, sequence, count, payload_size;
unsigned phase, mailbox_size;
std::uint64_t tick;
bool active, sealed;
const char* diagnostic = "";

void put(unsigned at, unsigned value) {
    for (unsigned i = 0; i < 4; ++i)
        packet[at + i] = static_cast<unsigned char>(value >> (i * 8));
}

void begin(std::uint64_t value, unsigned next_phase) {
    if (sealed) {
        diagnostic = "resource packet was not acknowledged";
        return;
    }
    tick = value;
    phase = next_phase;
    count = payload_size = 0;
    active = true;
}

void end() {
    active = false;
}

const char* error() {
    return diagnostic;
}

int session(lua_State* L) {
    lua_pushnumber(L, configured_session);
    return 1;
}

unsigned get(unsigned at) {
    unsigned value = 0;
    for (unsigned i = 0; i < 4; ++i)
        value |= unsigned(packet[at + i]) << (i * 8);
    return value;
}

int audio_status(lua_State* L) {
    void* out = lua_newbuffer(L, audioStatusBytes);
    if (mailbox_size >= mailboxPayloadOffset)
        std::memcpy(out, packet + audioStatusOffset, audioStatusBytes);
    else
        std::memset(out, 0, audioStatusBytes);
    return 1;
}

int results(lua_State* L) {
    lua_newtable(L);
    if (!mailbox_size)
        return 1;
    if (mailbox_size < mailboxPayloadOffset || mailbox_size > mailboxCapacity ||
        get(0) != mailboxMagic || get(4) > mailboxMaxRecords || get(8) != mailbox_size ||
        get(12) != configured_session)
        luaL_error(L, "invalid resource mailbox");
    const unsigned total = get(4);
    for (unsigned i = 0; i < total; ++i) {
        const unsigned at = mailboxHeaderBytes + i * mailboxRecordBytes, offset = get(at + 16),
                       length = get(at + 20);
        if (offset < mailboxPayloadOffset || offset > mailbox_size ||
            length > mailbox_size - offset)
            luaL_error(L, "invalid readback completion");
        lua_newtable(L);
        const char* names[] = {"id", "format", "width", "height"};
        for (unsigned j = 0; j < 4; ++j) {
            lua_pushnumber(L, get(at + j * 4));
            lua_setfield(L, -2, names[j]);
        }
        void* bytes = lua_newbuffer(L, length);
        std::memcpy(bytes, packet + offset, length);
        lua_setfield(L, -2, "bytes");
        lua_rawseti(L, -2, static_cast<int>(i + 1));
    }
    mailbox_size = 0;
    return 1;
}

unsigned integer(lua_State* L, int index) {
    const double value = luaL_checknumber(L, index);
    if (!std::isfinite(value) || value < 0 || value > U32_MAX || value != std::floor(value))
        luaL_argerror(L, index, "invalid resource integer");
    return static_cast<unsigned>(value);
}

int emit(lua_State* L) {
    if (!configured_session || !active || sealed || diagnostic[0])
        luaL_error(L, "resource operations require configured init/update");
    const unsigned op = integer(L, 1), id = integer(L, 2);
    std::size_t args_size, data_size;
    const void* args = luaL_checkbuffer(L, 3, &args_size);
    const void* data = luaL_checkbuffer(L, 4, &data_size);
    const unsigned start = (payload_size + 3) & ~3u;
    if ((args_size != 0 && args_size != descriptorBytes) || count >= maxCommands ||
        args_size > maxPayload || data_size > maxPayload ||
        start + args_size + data_size > maxPayload)
        luaL_error(L, "resource staging capacity or descriptor length invalid");
    std::memset(packet + headerBytes + count * commandBytes, 0, commandBytes);
    const unsigned at = headerBytes + count * commandBytes;
    packet[at] = static_cast<unsigned char>(op);
    packet[at + 1] = static_cast<unsigned char>(op >> 8U);
    packet[at + 2] = commandBytes;
    put(at + 8, id);
    put(at + 12, args_size ? start : 0);
    put(at + 16, static_cast<unsigned>(args_size));
    put(at + 20, data_size ? start + static_cast<unsigned>(args_size) : 0);
    put(at + 24, static_cast<unsigned>(data_size));
    if (args_size)
        std::memcpy(packet + payload_base + start, args, args_size);
    if (data_size)
        std::memcpy(packet + payload_base + start + args_size, data, data_size);
    payload_size = start + static_cast<unsigned>(args_size + data_size);
    ++count;
    return 0;
}
} // namespace resource_transport

extern "C" {
EMSCRIPTEN_KEEPALIVE unsigned game_resource_protocol() {
    if (game_profile() == console_constants::PROFILE_ALPHA_3D)
        return console_constants::ALPHA_3D_PROTOCOL;
    if (game_profile() == console_constants::PROFILE_TEXTURED_3D)
        return console_constants::TEXTURED_3D_PROTOCOL;
    return game_profile() == console_constants::PROFILE_3D ? console_constants::PREVIEW_3D_PROTOCOL
                                                           : console_constants::RESOURCE_PROTOCOL;
}

EMSCRIPTEN_KEEPALIVE unsigned game_resource_configure(unsigned session) {
    using namespace resource_transport;
    if (!session || active || sealed)
        return 0;
    configured_session = session;
    sequence = count = payload_size = mailbox_size = 0;
    diagnostic = "";
    return 1;
}

EMSCRIPTEN_KEEPALIVE const unsigned char* game_commit() {
    using namespace resource_transport;
    if (!configured_session)
        return nullptr;
    if (active || sealed || sequence == U32_MAX || diagnostic[0]) {
        diagnostic = "cannot seal resource packet";
        return nullptr;
    }
    ++sequence;
    const unsigned offset = headerBytes + count * commandBytes;
    std::memmove(packet + offset, packet + payload_base, payload_size);
    std::memset(packet, 0, headerBytes);
    const unsigned fields[] = {magic,
                               abi,
                               headerBytes,
                               configured_session,
                               static_cast<unsigned>(tick),
                               static_cast<unsigned>(tick >> 32U),
                               phase,
                               sequence,
                               count,
                               headerBytes,
                               count * commandBytes,
                               offset,
                               payload_size};
    for (unsigned i = 0; i < 13; ++i)
        put(i * 4, fields[i]);
    sealed = true;
    return packet;
}

EMSCRIPTEN_KEEPALIVE unsigned game_commit_size() {
    using namespace resource_transport;
    return headerBytes + count * commandBytes + payload_size;
}

EMSCRIPTEN_KEEPALIVE unsigned game_commit_ack(unsigned value) {
    using namespace resource_transport;
    if (!sealed || value != sequence) {
        diagnostic = "resource acknowledgement mismatch";
        return 0;
    }
    sealed = false;
    return 1;
}

EMSCRIPTEN_KEEPALIVE unsigned char* game_resource_mailbox() {
    return resource_transport::packet;
}

EMSCRIPTEN_KEEPALIVE unsigned game_resource_mailbox_capacity() {
    return resource_schema::mailboxCapacity;
}

EMSCRIPTEN_KEEPALIVE unsigned game_resource_mailbox_size(unsigned size) {
    if (size > resource_schema::mailboxCapacity)
        return 0;
    resource_transport::mailbox_size = size;
    return 1;
}
}
