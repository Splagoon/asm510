# ASM510

A simple assembler for the Sharp SM510, the 4-bit microcomputer that powered the original Game & Watch handhelds. Syntax is inspired by the GNU Assembler. Supports macros and expressions.

Check out the [example program](test/input/test.s) to get an idea of the syntax.

## Usage

The assembler should run on any system with [Erlang/OTP 25](https://www.erlang.org/downloads/25) installed. It is tested on Windows 11 using Git Bash.

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

#### `.endm`

Closes a macro body opened by `.macro`.

#### `.endr`

Closes a loop body opened by `.rept` or `.irp`.

#### `.err` [_message_]

Immediately exits the assembly process and prints an error. Useful when combined with conditional directives to fail assembly if certain conditions aren't met. Optionally accepts a string message explaining the error.

For example:

```asm
.ifndef foo
.err "foo is not defined"
.endif
```

#### `.exitm`

When inside a macro body, skips expanding the rest of the current macro. Useful when combined with conditional directives to exit the macro if certain conditions aren't met. Note that `.exitm` does _not_ close the macro body, so `.endm` is still necessary.

For example:

```asm
.macro add_1_if_even x
# Exit the macro if x is odd
.if \x % 2 > 0
.exitm
.endif
# Macro only gets this far if x is even
.set 'x, \x + 1
.endm
```

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

```asm
.word 1
.word 2
.word 3
```

#### `.macro ` _name_ [`, ` _arg_ [`=` _default_]]...\_

Defines a macro with the given _name_ and arguments and opens the macro body. When calling the macro, the macro body is assembled with each `\`_arg_ bound to the passed value, or _default_ if none was specified. The macro body must be closed by `.endm`.

For example, this definition specifies a macro `sum` that puts a sequence of numbers into the ROM:

```asm
.macro sum from=0, to=5
.word \from
.if \from < \to
sum \from + 1,\to
.endif
.endm
```

With that definition, `sum 0, 5` is equivalent to assembling:

```asm
.word 0
.word 1
.word 2
.word 3
.word 4
.word 5
```

If a macro argument specifies a default value, it can be omitted from the macro invocation by either skipping the argument with `,` or leaving it off the end of the arguments list. For example, given the earlier `sum` macro, all of the following invocations are equivalent:

```asm
sum 0, 5
sum 0,
sum 0
sum , 5
sum
```

Attempting to skip an argument that has no default will generate an error.

If you wish to refer to the **name** passed to an argument, refer to it as `'`_arg_. Some examples:

```asm
# Adds 1 to some_arg if it's defined, otherwise defines it was 1
.macro add_one some_arg
.ifndef 'some_arg
# If 'some_arg is undefined, then an expression was passed
.err "got expression, expected symbol"
.endif

.ifndef \some_arg
# If \some_arg is undefined, then define it as 1
.set 'some_arg, 1
.else
# If both 'some_arg and \some_arg are defined, then an identifier with a value
# was passed, and we can increment it
.set 'some_arg, \some_arg + 1
.endif
.endm

# 'some_arg will be "foo"
# \some_arg will be undefined because "foo" is undefined
# After invoking the macro, "foo" will be defined and set to 1
add_one foo

# 'some_arg will be undefined because an expression was passed
# \some_arg will be 2
add_one 1+1

# 'some_arg will be "foo"
# \some_arg will be 1
# After invoking the macro, "foo" will be set to 2
add_one foo
```

In addition to the macro's arguments, the special variable `\@` is also available inside macros. This variable holds the number of macros that have been invoked so far this assembly. It is guaranteed to be unique for every macro invocation and is therefore useful for making sure macros define labels that don't collide.

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
