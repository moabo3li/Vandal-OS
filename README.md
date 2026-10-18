# Vandal OS

Vandal OS is a small 32-bit RISC-V kernel.

## What works

- The linker loads the kernel at `0x80200000`.
- The boot code sets the stack pointer and enters `kernel_main`.
- The kernel clears the BSS section and stays in an idle loop.
- `run.sh` builds the kernel with Clang and LLD, then starts it in QEMU.

## Run

```sh
./run.sh
```

The blank screen after OpenSBI is expected because the kernel does not print
anything yet. Press `Ctrl+A`, then `X`, to close QEMU.

## Tools used

- C11
- Clang and LLD
- QEMU `virt` for 32-bit RISC-V
- OpenSBI
- Jujutsu

## Reference

- [OS in 1,000 Lines](https://operating-system-in-1000-lines.vercel.app/)
