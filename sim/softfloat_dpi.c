#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
#include "softfloat.h"

static void begin_op(uint32_t rm)
{
    static const uint_fast8_t modes[5] = {
        softfloat_round_near_even, softfloat_round_minMag,
        softfloat_round_min, softfloat_round_max, softfloat_round_near_maxMag
    };
    softfloat_roundingMode = modes[rm];
    softfloat_detectTininess = softfloat_tininess_afterRounding;
    softfloat_exceptionFlags = 0;
}

uint32_t sf_f32(uint32_t op, uint32_t a, uint32_t b, uint32_t rm,
                uint32_t *flags)
{
    float32_t x = {a}, y = {b}, z;
    begin_op(rm);
    switch (op) {
    case 0: z = f32_add(x, y); break;
    case 1: z = f32_mul(x, y); break;
    case 2: z = f32_div(x, y); break;
    default: z = f32_sqrt(x); break;
    }
    *flags = softfloat_exceptionFlags;
    return z.v;
}

uint64_t sf_f64(uint32_t op, uint64_t a, uint64_t b, uint32_t rm,
                uint32_t *flags)
{
    float64_t x = {a}, y = {b}, z;
    begin_op(rm);
    switch (op) {
    case 0: z = f64_add(x, y); break;
    case 1: z = f64_mul(x, y); break;
    case 2: z = f64_div(x, y); break;
    default: z = f64_sqrt(x); break;
    }
    *flags = softfloat_exceptionFlags;
    return z.v;
}
#ifdef __cplusplus
}
#endif
