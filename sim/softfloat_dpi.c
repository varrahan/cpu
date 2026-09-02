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
    case 1: z = f32_sub(x, y); break;
    case 2: z = f32_mul(x, y); break;
    case 3: z = f32_div(x, y); break;
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
    case 1: z = f64_sub(x, y); break;
    case 2: z = f64_mul(x, y); break;
    case 3: z = f64_div(x, y); break;
    default: z = f64_sqrt(x); break;
    }
    *flags = softfloat_exceptionFlags;
    return z.v;
}

uint32_t sf_fma32(uint32_t op, uint32_t a, uint32_t b, uint32_t c,
                  uint32_t rm, uint32_t *flags)
{
    float32_t x = {a}, y = {b}, z = {c}, result;
    begin_op(rm);
    if (op >= 2) x.v ^= UINT32_C(0x80000000);
    if (op == 1 || op == 3) z.v ^= UINT32_C(0x80000000);
    result = f32_mulAdd(x, y, z);
    *flags = softfloat_exceptionFlags;
    return result.v;
}

uint64_t sf_fma64(uint32_t op, uint64_t a, uint64_t b, uint64_t c,
                  uint32_t rm, uint32_t *flags)
{
    float64_t x = {a}, y = {b}, z = {c}, result;
    begin_op(rm);
    if (op >= 2) x.v ^= UINT64_C(0x8000000000000000);
    if (op == 1 || op == 3) z.v ^= UINT64_C(0x8000000000000000);
    result = f64_mulAdd(x, y, z);
    *flags = softfloat_exceptionFlags;
    return result.v;
}

uint32_t sf_cmp32(uint32_t op, uint32_t a, uint32_t b, uint32_t *flags)
{
    float32_t x = {a}, y = {b};
    uint32_t result;
    begin_op(0);
    result = op == 0 ? f32_le(x, y) : op == 1 ? f32_lt(x, y) : f32_eq(x, y);
    *flags = softfloat_exceptionFlags;
    return result;
}

uint32_t sf_cmp64(uint32_t op, uint64_t a, uint64_t b, uint32_t *flags)
{
    float64_t x = {a}, y = {b};
    uint32_t result;
    begin_op(0);
    result = op == 0 ? f64_le(x, y) : op == 1 ? f64_lt(x, y) : f64_eq(x, y);
    *flags = softfloat_exceptionFlags;
    return result;
}

uint64_t sf_convert(uint32_t op, uint64_t a, uint32_t rm, uint32_t *flags)
{
    float32_t x32 = {(uint32_t)a}, z32;
    float64_t x64 = {a}, z64;
    uint64_t result;
    begin_op(rm);
    switch (op) {
    case 0: result = (uint64_t)(int64_t)(int32_t)
        f32_to_i32(x32, softfloat_roundingMode, true); break;
    case 1: result = (uint64_t)(int64_t)(int32_t)
        f32_to_ui32(x32, softfloat_roundingMode, true); break;
    case 2: result = (uint64_t)(int64_t)(int32_t)
        f64_to_i32(x64, softfloat_roundingMode, true); break;
    case 3: result = (uint64_t)(int64_t)(int32_t)
        f64_to_ui32(x64, softfloat_roundingMode, true); break;
    case 4: z32 = i32_to_f32((int32_t)a); result = UINT64_C(0xffffffff00000000) | z32.v; break;
    case 5: z32 = ui32_to_f32((uint32_t)a); result = UINT64_C(0xffffffff00000000) | z32.v; break;
    case 6: z64 = i32_to_f64((int32_t)a); result = z64.v; break;
    case 7: z64 = ui32_to_f64((uint32_t)a); result = z64.v; break;
    case 8: z64 = f32_to_f64(x32); result = z64.v; break;
    default: z32 = f64_to_f32(x64); result = UINT64_C(0xffffffff00000000) | z32.v; break;
    }
    *flags = softfloat_exceptionFlags;
    return result;
}
#ifdef __cplusplus
}
#endif
