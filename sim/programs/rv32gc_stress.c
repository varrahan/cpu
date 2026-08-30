typedef unsigned int u32;
typedef signed int s32;

extern void isa_sweep(volatile u32 *out);

static u32 crc32(volatile u32 *values, u32 count)
{
    u32 crc = ~0u;
    u32 i, bit;

    for (i = 0; i < count; ++i) {
        crc ^= values[i];
        for (bit = 0; bit < 8; ++bit)
            crc = (crc >> 1) ^ (0xedb88320u & (0u - (crc & 1u)));
    }
    return ~crc;
}

static u32 sort_and_hash(volatile u32 *values, u32 count)
{
    u32 i, j, key, hash = 0;

    for (i = 1; i < count; ++i) {
        key = values[i];
        j = i;
        while (j && values[j - 1] > key) {
            values[j] = values[j - 1];
            --j;
        }
        values[j] = key;
    }
    for (i = 0; i < count; ++i)
        hash = hash * 33u + values[i];
    return hash;
}

static u32 matrix_checksum(volatile s32 *a, volatile s32 *b,
                           volatile s32 *c)
{
    u32 row, col, k, checksum = 0;

    for (row = 0; row < 3; ++row)
        for (col = 0; col < 3; ++col) {
            s32 sum = 0;
            for (k = 0; k < 3; ++k)
                sum += a[row * 3 + k] * b[k * 3 + col];
            c[row * 3 + col] = sum;
            checksum = checksum * 17u + (u32)sum;
        }
    return checksum;
}

static u32 gcd(u32 a, u32 b)
{
    while (b) {
        u32 remainder = a % b;
        a = b;
        b = remainder;
    }
    return a;
}

static u32 atomic_sweep(volatile u32 *word, u32 *history)
{
    u32 old, status, sum = 0;

    *word = 9;
    __asm__ volatile("lr.w %0, (%1)" : "=r"(old) : "r"(word) : "memory");
    sum += old;
    old = 12;
    __asm__ volatile("sc.w %0, %2, (%1)"
                     : "=r"(status) : "r"(word), "r"(old) : "memory");
    sum += status;
    old = 5;
    __asm__ volatile("amoswap.w %0, %2, (%1)"
                     : "=r"(old) : "r"(word), "r"(old) : "memory");
    sum += old;
#define AMO(OP, VALUE) do {                                                  \
        u32 value = (u32)(VALUE);                                            \
        __asm__ volatile(OP " %0, %2, (%1)"                                 \
                         : "=r"(old) : "r"(word), "r"(value) : "memory"); \
        sum += old;                                                          \
    } while (0)
    AMO("amoadd.w", 3);
    AMO("amoxor.w", 6);
    AMO("amoand.w", 10);
    AMO("amoor.w", 1);
    AMO("amomin.w", -2);
    AMO("amomax.w", 4);
    AMO("amominu.w", 3);
    AMO("amomaxu.w", 8);
#undef AMO
    *history = sum;
    return *word;
}

static u32 csr_sweep(void)
{
    u32 old0, old1, old2, old3, old4, old5, final;
    u32 value = 0x55, mask = 0x0f, clear = 3;

    __asm__ volatile("csrrw %0, mscratch, %1" : "=r"(old0) : "r"(value));
    __asm__ volatile("csrrs %0, mscratch, %1" : "=r"(old1) : "r"(mask));
    __asm__ volatile("csrrc %0, mscratch, %1" : "=r"(old2) : "r"(clear));
    __asm__ volatile("csrrwi %0, mscratch, 7" : "=r"(old3));
    __asm__ volatile("csrrsi %0, mscratch, 8" : "=r"(old4));
    __asm__ volatile("csrrci %0, mscratch, 1" : "=r"(old5));
    __asm__ volatile("csrr %0, mscratch" : "=r"(final));
    return old0 ^ (old1 << 1) ^ (old2 << 2) ^ (old3 << 3) ^
           (old4 << 4) ^ (old5 << 5) ^ (final << 6);
}

static u32 integer_mix(volatile u32 *seed)
{
    u32 x = seed[0], y = seed[1], shift = seed[2] & 31;
    s32 sx = (s32)x, sy = (s32)y;
    u32 result = (x + y) ^ (x - y);

    result ^= x << shift;
    result ^= y >> shift;
    result ^= (u32)(sx >> shift);
    result ^= (x < y) | ((u32)(sx < sy) << 1);
    result ^= (x & y) | (x ^ y) | (x | y);
    result ^= (x / (y | 1u)) + (x % (y | 1u));
    return result;
}

__attribute__((noinline, used)) void stress(void)
{
    volatile u32 *out = (volatile u32 *)0x400;
    volatile u32 *atomic_word = (volatile u32 *)0x300;
    volatile u32 values[8];
    volatile s32 a[9], b[9], c[9];
    volatile u32 seed[3];
    volatile u32 gcd_a = 1071, gcd_b = 462;
    union { float f; u32 u; } single;
    volatile s32 fp_seed = 3;
    float fa, fb, fmadd, fsquare;
    double da, db, dmadd, dquot;
    u32 atomic_history;
    u32 i;

    values[0] = 13; values[1] = 7;  values[2] = 9;  values[3] = 1;
    values[4] = 5;  values[5] = 3;  values[6] = 11; values[7] = 2;
    for (i = 0; i < 9; ++i) {
        a[i] = (s32)i + 1;
        b[i] = 9 - (s32)i;
    }
    seed[0] = 0x12345678u;
    seed[1] = 0x13579bdfu;
    seed[2] = 7;

    out[1] = sort_and_hash(values, 8);
    out[2] = crc32(values, 8);
    out[3] = matrix_checksum(a, b, c);
    out[4] = gcd(gcd_a, gcd_b);
    out[5] = atomic_sweep(atomic_word, &atomic_history);
    out[6] = atomic_history;
    out[7] = csr_sweep();
    out[8] = integer_mix(seed);

    fa = (float)fp_seed;
    fb = (float)(fp_seed + 1);
    fmadd = fa * fb + fa;
    fsquare = fb * fb;
    __asm__ volatile("fsqrt.s %0, %1" : "=f"(fsquare) : "f"(fsquare));
    single.f = fmadd;
    out[9] = single.u;
    single.f = fsquare;
    out[10] = single.u;

    da = (double)fp_seed;
    db = (double)(fp_seed + 1);
    dmadd = da * db + da;
    dquot = db / da;
    *(volatile double *)(out + 12) = dmadd;
    *(volatile double *)(out + 14) = dquot;
    isa_sweep(out);

    __asm__ volatile("fence rw, rw\n\tfence.i" ::: "memory");
    out[0] = 0x600d600d;
}

__attribute__((naked, section(".text.start"))) void _start(void)
{
    __asm__ volatile(
        ".option push\n"
        ".option norvc\n"
        "li sp, 0x1ff0\n"
        "call stress\n"
        "1: wfi\n"
        "j 1b\n"
        ".option pop\n");
}
