# zlang v1.5 — Typed Stack VM Design

Status: Draft, pre-implementation.

## Goal

Replace the uniform `Value`-slot runtime with a **byte-addressable** stack and
**type-specialized** opcodes so that primitive types of different widths and
stack-allocated structs share a single, predictable memory model.

The frontend (Lexer, Parser, Resolver, TypeChecker) stays. This document covers
only the IR and runtime: bytecode, frame layout, calling convention, struct
layout.

---

## 1. Type primitives

Every value at runtime has a static type known to the compiler. The runtime
itself is untyped — bytecode encodes the type as part of the opcode. No tags,
no boxing.

| Type   | Size (bytes) | Alignment | Notes                                |
| ------ | ------------ | --------- | ------------------------------------ |
| `bool` | 1            | 1         | 0 = false, 1 = true. No other values.|
| `i32`  | 4            | 4         | Two's complement.                    |
| `i64`  | 8            | 8         | Two's complement.                    |
| `f64`  | 8            | 8         | IEEE-754 double.                     |
| struct | computed     | computed  | See §5.                              |

**Out of scope for v1.5:** `f32`, unsigned ints, strings, heap pointers, sum
types. The surface syntax `int` / `float` from v1.0 is dropped — users now
write `i32`, `i64`, `f64` explicitly. `int` aliases to `i64` for one release as
a deprecation path.

### Endianness

All multi-byte values are stored **little-endian** in the locals area, the
operand stack, and the constant pool. Matches host on x86_64 and ARM64, lets
us memcpy through the stack without per-load byteswaps.

---

## 2. Operand stack and locals

### 2.1 Operand stack

The operand stack is a flat `[]u8` plus a byte cursor `sp`. Every push/pop
specifies a width. Pushes and pops are **not** required to be aligned: the
compiler statically knows what sits at the top of the stack, so it emits a
load/store of the right width without needing alignment guarantees.

```
push_u32(v):  writeInt(stack[sp..sp+4], v); sp += 4
pop_u32():    sp -= 4; return readInt(stack[sp..sp+4])
```

### 2.2 Locals area

Each frame owns a contiguous `[]u8` for its locals, sized at compile time.
Locals are placed in **declaration order** at byte offsets that respect each
local's natural alignment.

```
offset(local_i) = align_up(offset(local_{i-1}) + size(local_{i-1}), align(local_i))
frame_size      = align_up(end_of_last_local, 8)
```

The compiler computes the offset for every local during resolution. `slot:
u32` in the AST is replaced by `byte_offset: u32` plus a `kind` discriminator
used to pick the right typed opcode at compile time.

### 2.3 Why byte-addressed instead of typed slots

Two reasons:
1. Structs can sit directly in the locals area at known offsets, no separate
   heap.
2. A future move toward WASM (see [[wasm-backend]] in the prior discussion)
   gets cheaper — WASM's `local.get/set` are slot-indexed but linear memory is
   byte-addressed, and this matches that split.

---

## 3. Opcode set

Specialized over shared. Every primitive op carries its operand type in the
opcode name. This costs ~3× the enum width vs. a type-prefix byte, but
eliminates one dispatch on every instruction and lets the VM's main switch
generate dense jump tables. The op space stays well under 256 — single-byte
opcodes are sufficient.

### 3.1 Constants and locals

| Opcode             | Operands         | Effect                                          |
| ------------------ | ---------------- | ----------------------------------------------- |
| `ConstI32`         | `u32` value      | Push 4 bytes.                                   |
| `ConstI64`         | `u64` value      | Push 8 bytes.                                   |
| `ConstF64`         | `u64` bit-pattern| Push 8 bytes.                                   |
| `ConstTrue`        | —                | Push 1 byte = 1.                                |
| `ConstFalse`       | —                | Push 1 byte = 0.                                |
| `LoadLocalI32`     | `u16` offset     | Push 4 bytes from `locals[offset..]`.           |
| `LoadLocalI64`     | `u16` offset     | Push 8 bytes.                                   |
| `LoadLocalF64`     | `u16` offset     | Push 8 bytes.                                   |
| `LoadLocalBool`    | `u16` offset     | Push 1 byte.                                    |
| `StoreLocalI32`    | `u16` offset     | Pop 4 bytes, write to `locals[offset..]`.       |
| `StoreLocalI64`    | `u16` offset     | Pop 8 bytes.                                    |
| `StoreLocalF64`    | `u16` offset     | Pop 8 bytes.                                    |
| `StoreLocalBool`   | `u16` offset     | Pop 1 byte.                                     |
| `LoadLocalBytes`   | `u16` offset, `u16` size | Push `size` bytes — struct loads.       |
| `StoreLocalBytes`  | `u16` offset, `u16` size | Pop `size` bytes — struct stores.       |

`u16` offsets cap a single frame at 64 KiB of locals. Generous given the
target use case; can grow to `u32` later behind a `WideOffset` prefix without
breaking encoding.

### 3.2 Arithmetic and comparison

For each `T ∈ {I32, I64, F64}`:

| Opcode    | Stack effect            |
| --------- | ----------------------- |
| `Add{T}`  | `T, T → T`              |
| `Sub{T}`  | `T, T → T`              |
| `Mul{T}`  | `T, T → T`              |
| `Div{T}`  | `T, T → T`              |
| `Neg{T}`  | `T → T`                 |
| `Lt{T}`   | `T, T → bool`           |
| `Lte{T}`  | `T, T → bool`           |
| `Gt{T}`   | `T, T → bool`           |
| `Gte{T}`  | `T, T → bool`           |
| `Eq{T}`   | `T, T → bool`           |
| `Neq{T}`  | `T, T → bool`           |

Division: integer ops trap on divide-by-zero; `DivF64` follows IEEE-754 (no
trap, produces inf/NaN).

### 3.3 Boolean

| Opcode    | Stack effect            |
| --------- | ----------------------- |
| `NotBool` | `bool → bool`           |
| `EqBool`  | `bool, bool → bool`     |
| `NeqBool` | `bool, bool → bool`     |

No `AndBool`/`OrBool` opcodes — short-circuit `&&`/`||` lower to branches.

### 3.4 Control flow

| Opcode        | Operands     | Effect                                              |
| ------------- | ------------ | --------------------------------------------------- |
| `Jump`        | `i16` offset | Unconditional relative branch.                      |
| `JumpIfFalse` | `i16` offset | Pop 1 byte; if 0, branch.                           |
| `JumpIfTrue`  | `i16` offset | Pop 1 byte; if 1, branch.                           |
| `Loop`        | `u16` offset | Unconditional backward branch.                      |

Offsets are signed (`Jump`/`JumpIfFalse`/`JumpIfTrue`) or unsigned
(`Loop`, kept as in v1.0 for backward-compat with existing patch logic) and
relative to the byte after the operand, same as v1.0.

### 3.5 Calls

| Opcode       | Operands                       | Effect                                  |
| ------------ | ------------------------------ | --------------------------------------- |
| `Call`       | `u32` fn_idx, `u16` args_bytes | See §4.                                 |
| `ReturnVoid` | —                              | Pop frame, no value transfer.           |
| `Return`     | `u16` size                     | Move top `size` bytes to caller's stack.|

`OP_CALL` from v1.0 is renamed `Call` and the trailing arg-count byte becomes
a 16-bit total **byte width** of the argument block, not a count. The callee
knows its own arity statically and doesn't need the count.

---

## 4. Calling convention

### 4.1 Argument passing

Caller-side:
1. Evaluate each argument left-to-right, leaving its bytes on the operand
   stack.
2. Emit `Call fn_idx, args_bytes` where `args_bytes` is the sum of the
   widths of all arguments (computed at compile time from the callee's
   signature).

Callee-side, executed by the VM on `Call`:
1. Allocate a new frame with the callee's known `frame_size`.
2. The top `args_bytes` of the caller's operand stack become the first
   `args_bytes` of the callee's locals area. Implementation: `memcpy` from
   `caller.stack[sp - args_bytes ..]` into `callee.locals[0 ..]`, then
   `caller.sp -= args_bytes`.
3. The callee's argument locals are therefore at offsets `0`,
   `align_up(size_0, align_1)`, etc. — the same offsets the compiler assigned
   when laying out the callee's locals.

This works because the compiler lays out parameters first in declaration
order, before any local variables, with the same alignment rule.

### 4.2 Return values

Callee-side, on `Return size`:
1. The top `size` bytes of the callee's operand stack are the return value.
2. Pop the frame; copy those `size` bytes onto the caller's operand stack.
3. Resume the caller at the instruction after `Call`.

`ReturnVoid` skips the copy. Functions with no declared return type compile
to `ReturnVoid`.

### 4.3 Struct returns

Aggregate returns work the same way — `Return 16` copies a 16-byte struct
onto the caller's stack. No special handling needed for "small" vs. "large"
structs in v1.5; revisit if profiling shows the copy is hot.

---

## 5. Struct layout

C-style natural alignment, no field reordering.

```
StructDecl {
  fields: [Field],
}

Field {
  name:   string,
  kind:   Type,
  offset: u32,   // byte offset within the struct, computed by the type checker
  size:   u32,   // derived from kind, cached so codegen doesn't re-switch
}
```

### 5.1 Offset computation

Walk fields in declaration order:

```
offset(field_0) = 0
offset(field_i) = align_up(offset(field_{i-1}) + size(field_{i-1}), align(field_i))
struct_align    = max(align(field_i) for all i)        // 1 if no fields
struct_size     = align_up(end_of_last_field, struct_align)
```

The trailing pad-to-`struct_align` matters so arrays of the struct (future
feature) keep every element aligned.

### 5.2 Examples

```
struct Point { x: i32, y: i32 }
  x @ 0, y @ 4, align = 4, size = 8

struct Mixed { flag: bool, value: i64 }
  flag @ 0, [7 bytes pad], value @ 8, align = 8, size = 16

struct Tight { a: bool, b: bool, c: i32 }
  a @ 0, b @ 1, [2 bytes pad], c @ 4, align = 4, size = 8
```

### 5.3 Field access

Field access compiles to byte arithmetic on the parent local's offset:

```
p.x   →   LoadLocalI32 <offset_of_p + 0>
p.y   →   LoadLocalI32 <offset_of_p + 4>
```

For nested structs and (future) pointers, this generalizes to a chain of
adds resolved at compile time — no runtime field lookup.

### 5.4 Construction

Struct literals compile to a sequence of stores into a freshly-reserved
local. The reservation happens at resolution time, the same way regular
locals do, so the struct's bytes live in the frame for its lexical scope.

---

## 6. AST and IR changes

### 6.1 ZType

Replace `Numeric { Int, Float }` with concrete-width kinds:

```zig
pub const Kind = union(enum) {
    bool_,
    i32,
    i64,
    f64,
    struct_: *const StructType,
};

pub const StructType = struct {
    name: []const u8,
    fields: []Field,
    size: u32,
    alignment: u8,
};

pub const Field = struct {
    name: []const u8,
    kind: Kind,
    offset: u32,
    size: u32,
};
```

`StructType.size`/`alignment` and every `Field.offset`/`size` are computed
once during type checking and cached. Codegen never recomputes them.

### 6.2 Resolver

`slot: u32` on every declaration becomes `offset: u32`. `maxSlots` becomes
`frame_size`. The slot allocator is replaced by a byte allocator that rounds
up to alignment on each allocation and tracks the high-water mark.

### 6.3 Compiler

Every `compileExpression` / `compileStatement` site that currently picks
between `LoadLocal`/`StoreLocal` etc. must also pick by type — the type comes
from the AST node, which the type checker has already resolved.

The functions emitted per arithmetic op grow from one branch to three (or
four including bool comparisons). Worth wrapping in a small `emitArith(op,
type)` helper.

---

## 7. Compatibility and migration

v1.5 is a runtime break. Bytecode produced by v1.0 will not run on the v1.5
VM. Source code that uses `int`/`float` keeps working in the first v1.5
release with a deprecation warning that points users to `i64`/`f64`. The
deprecation alias is removed in v1.6.

---

## 8. Open questions

- **Struct equality.** v1.5: omit `==` on structs entirely; users compare
  fields. v1.6 could add a generated `EqBytes size` opcode.
- **Stack overflow detection.** Currently `push` checks `sp >= stack.len`.
  With variable-width pushes this becomes `sp + width > stack.len`. Need to
  audit every emitter site.
- **Debug info.** The current `dumpProgram` prints opcodes and constants.
  With type-specialized opcodes the dump gets longer but more informative.
  No format change needed.
- **Alignment of the operand stack itself.** Current plan: the stack base is
  8-byte aligned (allocator gives us that), and we let `sp` go wherever it
  wants because reads/writes use `std.mem.readInt` which handles unaligned
  access. Revisit if we ever target a platform that traps on unaligned
  loads.

---

## 9. Implementation order (Phase 2 onward)

1. ZType: add `i32`/`i64`/`f64`/`bool`/`struct_` kinds, compute layout.
2. Resolver: switch slot allocator to byte allocator.
3. Bytecode: rewrite `Opcode` enum and `operandSize`.
4. Compiler: rewrite emission for every node type.
5. VM: rewrite stack as `[]u8`, rewrite dispatch loop, rewrite `FrameStore`.
6. Tests: golden bytecode tests for every primitive op; round-trip tests for
   recursive fib in each numeric type; struct construction + field access
   tests.
