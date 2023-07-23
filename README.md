# ASM510

A simple assembler for the Sharp SM510, the 4-bit microcomputer that powered the original Game & Watch handhelds. Syntax is inspired by the GNU Assembler.

Currently supports expressions, but not macros. (Maybe soon!)

Check out the [example program](test/input/test.s) to get an idea of the syntax.

## Usage

The assembler should run on any system with [Erlang/OTP 25](https://www.erlang.org/downloads/25) installed. It is tested on Windows 10 using Git Bash.

Download the [latest release](https://github.com/Splagoon/asm510/releases) and run it:

```sh
./asm510 input.s -o output.bin
```

(If the `-o`/`--out` flag is omitted, the output will be written to "out.bin")

### Assembler Directives

This assembler supports a number of assembler directives borrowed from the GNU Assembler. An expression can be used wherever a value argument is expected. Here is the complete list of all implemented assembler directives:

#### `.else`

When placed after `.if`, `.ifdef`, or `.ifndef`, this directive ends the positive conditional body and begins the negative conditional body. The body must be closed with `.endif`.

#### `.endif`

Closes a conditional body opened by `.if`, `.ifdef`, `ifndef`, or `else`.

#### `.endr`

Closes a loop body opened by `.rept` or `.irp`.

#### `.err`

Immediately exits the assembly process and prints an error. Useful when combined with conditional directives to fail assembly if certain conditions aren't met.

#### `.if ` _condition_

Opens a conditional body. The argument is an expression to be evaluated during assembly. If the expression evaluates to any nonzero value, the conditional body is assembled. If the expression evaluates to zero, the conditional body is skipped and, if present, the `.else` body is assembled. The conditional body must be closed by `.endif` or `.else`.

For example:
```s
.if X + 1
# Code here is assembled if X + 1 != 0
.else
# Code here is assembled if X + 1 == 0
.endif
```

#### `.ifdef ` _symbol_

Same as `.if`, but the argument is a symbol. If the symbol exists (e.g. it was declared with `.set`), the conditional body will be assembled.

#### `.ifndef ` _symbol_

Same as `.ifdef`, but only assembles the conditional body if the argument symbol is _not_ defined.

#### `.irp ` _symbol_ `, ` _values..._

Opens a loop body. For each value in _values_, the loop body is assembled with `\`_symbol_ bound to the current value. The loop body must be closed by `.endr`.

For example, assembling
```asm
.irp x, 1, 2, 3
.word \x
.endif
```
is equivalent to assembling
```
.word 1
.word 2
.word 3
```

#### `.org ` _location_

Sets the location counter to the value of _location_. The location counter can be moved anywhere, forwards or backwards, and there are (currently) no protections for moving the location counter over previously-emitted locations or out of bounds.

#### `.rept ` _count_

Opens a loop body, which will be assembled _count_ times. The loop body must be closed by `.endr`.

For example, assembling
```asm
.rept 3
.word 1
.endr
```
is equiavlent to assembling
```
.word 1
.word 1
.word 1
```

#### `.set` _symbol_ `, ` _expression_

Sets the value of _symbol_ to _expression_. The symbol is declared if it does not exist. If the symbol already exists, its value will be overwritten.

#### `.skip ` _size_ `, ` [_fill_]

Emits _size_ bytes with _fill_ value. If _fill_ is not specified, it defaults to zero.

#### `.word ` _expression_

Emits one byte with the value of _expression_.
