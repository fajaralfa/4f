# 4F

An imaginary 16 bit CPU environment

## Notes

It's a project intended for me learn how computer works at the lowest level, potentially educational for others.

## Project Content

- [ISA Spec](#isa-spec)
- Emulator
- Assembler

## ISA Spec

### Register

- Register is 3 bit address that hold 16 bit value

| ABI Name | Register | Description | Register Address |
| - | - | - | - |
| pc | r0 | Program Counter | 0x00 |
| sp | r1 | Stack Pointer | 0x01 |
| x1 | r2 | General Purpose | 0x02 |
| x2 | r3 | General Purpose | 0x03 |
| x3 | r4 | General Purpose | 0x04 |
| mepc | r5 | Exception Program Counter | 0x05 |
| mcause | r6 | Cause of Exception | 0x06 |
| mtvec | r7 | Trap Handler Address | 0x07 |

### Memory

- 64KB address space (16 bit addresses)

### Instruction

#### Encoding:

- Little Endian is used for 16 bit values in memory.

#### Instruction Set:

- value is two's complement
- word is 16 bit value

| Opcode | Machine Code | Mnemonic | Fields Size | Operation |
| - | - | - | - | - |
| lw | 0x01 | lw x1, x2, 5 | 5, 3, 3, 5 (op, dest, base, offset) | x1 = mem[x2 + (offset * 2)] |
| sw | 0x02 | sw x1, x2, 5 | 5, 3, 3, 5 (op, src, base, offset) | mem[x2 + (offset * 2)] = x1 |
| lui | 0x03 |lui x1, #0xFF | 5, 3, 8 (op, dest, val) | x1 = 0xFF << 8 |
| addi | 0x04 | addi x1, x2, #0x1F | 5, 3, 3, 5 (op, dest, src, val) | x1 = x2 + 0x1F |
| add | 0x05 |add x1, x2, x3 | 5, 3, 3, 3, 2 (op, dest, src1, src2, pad) | x1 = x2 + x3 |
| sub | 0x06 |sub x1, x2, x3 | 5, 3, 3, 3, 2 (op, dest, src1, src2, pad) | x1 = x2 - x3 |
| and | 0x07 |and x1, x2, x3 | 5, 3, 3, 3, 2 (op, dest, src1, src2) | x1 = x2 & x3 |
| not | 0x08 |not x1, x2 | 5, 3, 3, 5 (op, dest, src1, pad) | x1 = ~x2 |
| or | 0x09 | or x1, x2, x3 | 5, 3, 3, 3, 2 (op, dest, src1, src2) | x1 = x2 OR x3|
| xor | 0x0a |xor x1, x2, x3 | 5, 3, 3, 3, 2 (op, dest, src1, src2) | x1 = x2 ^ x3 |
| sll | 0x0b |sll x1, x2, x3 | 5, 3, 3, 3, 2 (op, dest, src1, src2) | x1 = x2 << x3 |
| srl | 0x0c |srl x1, x2, x3 | 5, 3, 3, 3, 2 (op, dest, src1, src2) | x1 = x2 >> x3 |
| sra | 0x0d |sra x1, x2, x3 | 5, 3, 3, 3, 2 (op, dest, src1, src2) | x1 = x2 >>> x3 |
| jr | 0x0e | jr x1 | 5, 3, 8 (op, dest, pad) | PC += x1 * 2 |
| beq | 0x0f |beq x1, x2, x3 | 5, 3, 3, 3, 2 (op, dest, src1, src2) | if (x2 == x3) PC += x1 * 2 |
| bne | 0x10 |bne x1, x2, x3 | 5, 3, 3, 3, 2 (op, dest, src1, src2) | if (x2 != x3) PC += x1 * 2 |
| halt | 0x1F | halt | 5, 11 (op, pad) | stop cpu |

## Footnote

Missing features:
- ISA Spec:
    - Memory layout
- Assembler:
    - Label resolver
    - Expression
- Emulator:
    - Exception handler
