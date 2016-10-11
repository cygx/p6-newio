#include <stdint.h>

/*
    A synthetic is defined as a non-empty sequence of 32-bit units where
    the highest 4 bits of the first one determine the type of the synthetic.

    If no type bits are set, we're dealing with a regular normalized
    sequence of Unicode codepoint, starting at the first unit.

    If only the most significant type bit is set, we're dealing with a denormal
    sequence of Unicode codepoints, with the first codepoint encoded in the 28
    lower bits of the first unit.

    In addition, there are compatibility modes for 8-, 16- and 32-bit encodings.
    As synthetic units are 32-bit, the first unit is a header that contains
    the number of value bytes in the compatibility sequence, which starts at
    the first byte of the second unit and continues in natural byte order.
*/

#define SYNTH32_REGULAR  (0u)
#define SYNTH32_DENORMAL (0x8u << 28)
#define SYNTH32_COMPAT8  (0x9u << 28)
#define SYNTH32_COMPAT16 (0xAu << 28)
#define SYNTH32_COMPAT32 (0xBu << 28)

static inline uint32_t synth32_type(const uint32_t *units) {
    return *units & 0xF0000000;
}

static inline uint32_t synth32_is_type(const uint32_t *units, uint32_t type) {
    return synth32_type(units) == type;
}

static inline uint32_t synth32_first(const uint32_t *units) {
    return *units & 0x0FFFFFFF;
}

static inline uint32_t synth32_compat_bytes(const uint32_t *units) {
    return synth32_first(units);
}

static inline const uint8_t *synth32_as_compat8(const uint32_t *units) {
    return (const uint8_t *)(units + 1);
}

static inline const uint16_t *synth32_as_compat16(const uint32_t *units) {
    return (const uint16_t *)(units + 1);
}

static inline const uint32_t *synth32_as_compat32(const uint32_t *units) {
    return units + 1;
}

static void synth32_mark_denormal(uint32_t *unit) {
    *unit |= SYNTH32_DENORMAL;
}

static inline uint32_t synth32_compat_header(uint32_t type, uint32_t num_bytes) {
    return type | num_bytes;
}
