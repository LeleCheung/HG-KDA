VARIANT ?= kji
NAME = xsai-gemm-heldout-$(VARIANT)
SRCS = main.c

override ARCH ?= riscv64-xs
override TOOLCHAIN ?= LLVM

CPPFLAGS += -DGEMM_VARIANT=$(VARIANT)

include $(AM_HOME)/Makefile.app

