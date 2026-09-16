#include <klib.h>

#define N 8

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

int main(void) {
  int i, j, k, checksum = 0;
  unsigned long cycle0, cycle1, inst0, inst1;
  for (i = 0; i < N; i++) for (j = 0; j < N; j++) {
    a[i][j] = (i + 2 * j) % 7 - 3;
    b[i][j] = (3 * i - j) % 5 - 2;
    c[i][j] = 0;
  }
  inst0 = read_minstret();
  cycle0 = read_mcycle();
  for (i = 0; i < N; i++)
    for (j = 0; j < N; j++)
      for (k = 0; k < N; k++) c[i][j] += a[i][k] * b[k][j];
  cycle1 = read_mcycle();
  inst1 = read_minstret();
  for (i = 0; i < N; i++) for (j = 0; j < N; j++) checksum += c[i][j];
  printf("GEMM ijk checksum=%d kernel_cycles=%lu kernel_instr=%lu\n",
         checksum, cycle1 - cycle0, inst1 - inst0);
  return checksum == 119 ? 0 : 1;
}
