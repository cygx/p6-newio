#include <stdint.h>

/*
    A synthetic is defined as a non-empty sequence of 32-bit units where
    the highest 8 bits of the first one determine the type of the synthetic.

    If no type bits are set, we're dealing with a regular normalized
    sequence of Unicode codepoint, starting at the first unit.

    If only the most significant type bit is set, we're dealing with a denormal
    sequence of Unicode codepoints, with the first codepoint encoded in the 24
    lower bits of the first unit.

    In addition, there are compatibility modes for 8-, 16- and 32-bit encodings.
    As synthetic units are 32-bit, the first unit is a header that determines
    the number of padding bytes at the end of the last unit.
    The compatibility sequence starts at the first byte of the second unit and
    continues in natural byte order.
*/

#define SYNTH32_REGULAR  (0u)
#define SYNTH32_DENORMAL (0x80u << 24)
#define SYNTH32_COMPAT8  (0x81u << 24)
#define SYNTH32_COMPAT16 (0x82u << 24)
#define SYNTH32_COMPAT32 (0x83u << 24)

static inline uint32_t synth32_type(const uint32_t *codes) {
    return *codes & 0xFF000000;
}

static inline uint32_t synth32_is_type(const uint32_t *codes, uint32_t type) {
    return *codes & type;
}

static inline uint32_t synth32_first(const uint32_t *codes) {
    return *codes & 0x00FFFFFF;
}

static inline uint32_t synth32_compat_bytes(const uint32_t *codes, uint32_t num) {
    return (num - 1) * 4 - synth32_first(codes);
}

static inline const uint8_t *synth32_as_compat8(const uint32_t *codes) {
    return (const uint8_t *)(codes + 1);
}

static inline const uint16_t *synth32_as_compat16(const uint32_t *codes) {
    return (const uint16_t *)(codes + 1);
}

static inline const uint32_t *synth32_as_compat32(const uint32_t *codes) {
    return codes + 1;
}

static void synth32_mark_denormal(uint32_t *code) {
    *code |= SYNTH32_DENORMAL;
}

static inline uint32_t synth32_header_for_compat8(uint32_t num_bytes) {
    return SYNTH32_COMPAT8 | (4 - num_bytes % 4) % 4;
}

static inline uint32_t synth32_header_for_compat16(uint32_t num_words) {
    return SYNTH32_COMPAT16 | (num_words % 2) * 2;
}

static inline uint32_t synth32_header_for_compat32(uint32_t num_dwords) {
    (void)num_dwords;
    return SYNTH32_COMPAT32;
}
