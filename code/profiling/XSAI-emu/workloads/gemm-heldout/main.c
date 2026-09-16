#include <klib.h>

#ifndef GEMM_VARIANT
#define GEMM_VARIANT kji
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

__attribute__((noinline, used)) static void kernel_kji(void) {
  int i, j, k;
  for (k = 0; k < N; k++)
    for (j = 0; j < N; j++) {
      int bkj = b[k][j];
      for (i = 0; i < N; i++) c[i][j] += a[i][k] * bkj;
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

__attribute__((noinline, used)) static void kernel_reg4x4(void) {
  int i, j, k;
  for (i = 0; i < N; i += 4)
    for (j = 0; j < N; j += 4) {
      int acc[4][4] = {{0}};
      for (k = 0; k < N; k++) {
        int ii, jj;
        for (ii = 0; ii < 4; ii++)
          for (jj = 0; jj < 4; jj++)
            acc[ii][jj] += a[i + ii][k] * b[k][j + jj];
      }
      for (int ii = 0; ii < 4; ii++)
        for (int jj = 0; jj < 4; jj++) c[i + ii][j + jj] = acc[ii][jj];
    }
}

__attribute__((noinline, used)) static void kernel_reg8x8(void) {
  int i, j, k;
  for (i = 0; i < N; i += 8)
    for (j = 0; j < N; j += 8) {
      int acc[8][8] = {{0}};
      for (k = 0; k < N; k++) {
        int ii, jj;
        for (ii = 0; ii < 8; ii++)
          for (jj = 0; jj < 8; jj++)
            acc[ii][jj] += a[i + ii][k] * b[k][j + jj];
      }
      for (int ii = 0; ii < 8; ii++)
        for (int jj = 0; jj < 8; jj++) c[i + ii][j + jj] = acc[ii][jj];
    }
}

#define RUN_VARIANT_kji() kernel_kji()
#define RUN_VARIANT_ikj() kernel_ikj()
#define RUN_VARIANT_reg4x4() kernel_reg4x4()
#define RUN_VARIANT_reg8x8() kernel_reg8x8()
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
  printf("HELDOUT variant=%s n=%d repeats=%d checksum=%d kernel_cycles=%lu kernel_instr=%lu\n",
         STR(GEMM_VARIANT), N, REPEATS, checksum,
         cycle1 - cycle0, inst1 - inst0);
  return checksum == 295 ? 0 : 1;
}

