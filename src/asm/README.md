# Assembler

Grammar:

```
program -> block*
block -> (label ':') | instruction
instruction -> opcode (operand (',' operand)*)?
opcode -> Defined in spec
operand -> register | immediate | label
register -> 'pc' | 'sp' | 'x1' | 'x2' | 'x3' | 'mepc' | 'mcause' | 'mtvec'
immediate -> # (dec | hex | oct | bin)
label -> ('a' - 'z' | 'A' - 'Z' | '_')+
```