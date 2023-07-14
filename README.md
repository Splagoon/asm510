# ASM510

A simple assembler for the Sharp SM510, the 4-bit microcomputer that powered the original Game & Watch handhelds. Syntax is inspired by the GNU Assembler.

Currently supports expressions, but not macros. (Maybe soon!)

Not well documented yet, but see the [example program](test/input/test.s) to get an idea of the syntax.

## Usage

The assembler should run on any system with [Erlang/OTP 25](https://www.erlang.org/downloads/25) installed. It is tested on Windows 10 using Git Bash.

Download the [latest release](https://github.com/Splagoon/asm510/releases) and run it:

```sh
./asm510 input.s -o output.bin
```

(If the `-o`/`--out` flag is omitted, the output will be written to "out.bin")
