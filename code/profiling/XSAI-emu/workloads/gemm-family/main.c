#include <klib.h>

#ifndef GEMM_VARIANT
#define GEMM_VARIANT ijk
#endif

#define N 16
#define REPEATS 4
#define STR_IMPL(x) #x
#define STR(x) STR_IMPL(x)

static int a[N][N], b[N][N], c[N][N];

static inline unsigned long read_mcycle(void) {
  unsigned long value;
  asm volatile("csrr %0, mcycle" : "=r"(value) :: "memory");
  return value;
}

static inline unsigned long read_minstret(void) {
  unsigned long value;
  asm volatile("csrr %0, minstret" : "=r"(value) :: "memory");
  return value;
}

static void reset_c(void) {
  int i, j;
  for (i = 0; i < N; i++)
    for (j = 0; j < N; j++) c[i][j] = 0;
}

__attribute__((noinline, used)) static void kernel_ijk(void) {
  int i, j, k;
  for (i = 0; i < N; i++)
    for (j = 0; j < N; j++) {
      int sum = 0;
      for (k = 0; k < N; k++) sum += a[i][k] * b[k][j];
      c[i][j] = sum;
    }
}

__attribute__((noinline, used)) static void kernel_ikj(void) {
  int i, j, k;
  for (i = 0; i < N; i++)
    for (k = 0; k < N; k++) {
      int aik = a[i][k];
      for (j = 0; j < N; j++) c[i][j] += aik * b[k][j];
    }
}

__attribute__((noinline, used)) static void kernel_jki(void) {
  int i, j, k;
  for (j = 0; j < N; j++)
    for (k = 0; k < N; k++) {
      int bkj = b[k][j];
      for (i = 0; i < N; i++) c[i][j] += a[i][k] * bkj;
    }
}

__attribute__((noinline, used)) static void kernel_reg2x2(void) {
  int i, j, k;
  for (i = 0; i < N; i += 2)
    for (j = 0; j < N; j += 2) {
      int c00 = 0, c01 = 0, c10 = 0, c11 = 0;
      for (k = 0; k < N; k++) {
        int a0 = a[i][k], a1 = a[i + 1][k];
        int b0 = b[k][j], b1 = b[k][j + 1];
        c00 += a0 * b0;
        c01 += a0 * b1;
        c10 += a1 * b0;
        c11 += a1 * b1;
      }
      c[i][j] = c00;
      c[i][j + 1] = c01;
      c[i + 1][j] = c10;
      c[i + 1][j + 1] = c11;
    }
}

__attribute__((noinline, used)) static void kernel_reg4x4(void) {
  int i, j, k;
  for (i = 0; i < N; i += 4)
    for (j = 0; j < N; j += 4) {
      int c00 = 0, c01 = 0, c02 = 0, c03 = 0;
      int c10 = 0, c11 = 0, c12 = 0, c13 = 0;
      int c20 = 0, c21 = 0, c22 = 0, c23 = 0;
      int c30 = 0, c31 = 0, c32 = 0, c33 = 0;
      for (k = 0; k < N; k++) {
        int a0 = a[i][k], a1 = a[i + 1][k];
        int a2 = a[i + 2][k], a3 = a[i + 3][k];
        int b0 = b[k][j], b1 = b[k][j + 1];
        int b2 = b[k][j + 2], b3 = b[k][j + 3];
        c00 += a0 * b0; c01 += a0 * b1;
        c02 += a0 * b2; c03 += a0 * b3;
        c10 += a1 * b0; c11 += a1 * b1;
        c12 += a1 * b2; c13 += a1 * b3;
        c20 += a2 * b0; c21 += a2 * b1;
        c22 += a2 * b2; c23 += a2 * b3;
        c30 += a3 * b0; c31 += a3 * b1;
        c32 += a3 * b2; c33 += a3 * b3;
      }
      c[i][j] = c00; c[i][j + 1] = c01;
      c[i][j + 2] = c02; c[i][j + 3] = c03;
      c[i + 1][j] = c10; c[i + 1][j + 1] = c11;
      c[i + 1][j + 2] = c12; c[i + 1][j + 3] = c13;
      c[i + 2][j] = c20; c[i + 2][j + 1] = c21;
      c[i + 2][j + 2] = c22; c[i + 2][j + 3] = c23;
      c[i + 3][j] = c30; c[i + 3][j + 1] = c31;
      c[i + 3][j + 2] = c32; c[i + 3][j + 3] = c33;
    }
}

#define RUN_VARIANT_ijk() kernel_ijk()
#define RUN_VARIANT_ikj() kernel_ikj()
#define RUN_VARIANT_jki() kernel_jki()
#define RUN_VARIANT_reg2x2() kernel_reg2x2()
#define RUN_VARIANT_reg4x4() kernel_reg4x4()
#define RUN_VARIANT_INNER(x) RUN_VARIANT_##x()
#define RUN_VARIANT(x) RUN_VARIANT_INNER(x)

int main(void) {
  int i, j, repeat, checksum = 0;
  unsigned long cycle0, cycle1, inst0, inst1;

  for (i = 0; i < N; i++)
    for (j = 0; j < N; j++) {
      a[i][j] = (i + 2 * j) % 7 - 3;
      b[i][j] = (3 * i - j) % 5 - 2;
    }

  inst0 = read_minstret();
  cycle0 = read_mcycle();
  for (repeat = 0; repeat < REPEATS; repeat++) {
    reset_c();
    RUN_VARIANT(GEMM_VARIANT);
  }
  cycle1 = read_mcycle();
  inst1 = read_minstret();

  for (i = 0; i < N; i++)
    for (j = 0; j < N; j++) checksum += c[i][j];

  printf("GEMM variant=%s n=%d repeats=%d checksum=%d kernel_cycles=%lu kernel_instr=%lu\n",
         STR(GEMM_VARIANT), N, REPEATS, checksum,
         cycle1 - cycle0, inst1 - inst0);
  printf("PROFILE_WINDOW start_instr=%lu end_instr=%lu\n", inst0, inst1);
  return checksum == 295 ? 0 : 1;
}
