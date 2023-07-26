defmodule ASM510.GeneratorTest do
  use ExUnit.Case

  alias ASM510.{Lexer, Parser, Generator}

  test "conditionals" do
    input1 =
      &"""
      .set x, #{&1}
      .if x
      .word 0xAB
      .endif
      """

    input2 =
      &"""
      .set x, #{&1}
      .if x
      .word 0xAB
      .else
      .word 0xCD
      .endif
      """

    for {input, x, output} <- [
          {input1, 1, 0xAB},
          {input1, 0, 0},
          {input2, 1, 0xAB},
          {input2, 0, 0xCD}
        ] do
      with {:ok, tokens} <- Lexer.lex(input.(x)),
           {:ok, syntax} <- Parser.parse(tokens),
           {:ok, rom} <- Generator.generate(syntax, 1) do
        assert rom == <<output::8>>
      else
        error -> flunk("Got error: #{inspect(error)}")
      end
    end
  end

  test "ifdef/ifndef directives" do
    # Both of these programs should be equivalent
    input1 = """
    .ifdef x
    .err
    .else
    .set x, 0x12
    .endif
    .word x
    """

    input2 = """
    .ifndef x
    .set x, 0x12
    .else
    .err
    .endif
    .word x
    """

    for input <- [input1, input2] do
      with {:ok, tokens} <- Lexer.lex(input),
           {:ok, syntax} <- Parser.parse(tokens),
           {:ok, rom} <- Generator.generate(syntax, 1) do
        assert rom == <<0x12::8>>
      else
        error -> flunk("Got error: #{inspect(error)}")
      end
    end
  end

  test "err directive" do
    test_input = ".err"

    with {:ok, tokens} <- Lexer.lex(test_input),
         {:ok, syntax} <- Parser.parse(tokens) do
      assert Generator.generate(syntax) == {:error, 1, :err_directive}
    end
  end

  test "rept directive" do
    test_input = """
    .set x, 0
    .rept 3
    .org 0
    .set x, x + 1
    .word x
    .endr
    """

    with {:ok, tokens} <- Lexer.lex(test_input),
         {:ok, syntax} <- Parser.parse(tokens),
         {:ok, rom} <- Generator.generate(syntax, 1) do
      assert rom == <<3::8>>
    else
      error -> flunk("Got error: #{inspect(error)}")
    end
  end

  test "error in scope body" do
    test_input = """
    .ifdef test
    .err
    .else
    .if 1
    .irp x, 1, 2, 3
    .rept 3
    .word undefined
    .endr
    .endr
    .endif
    .endif
    """

    with {:ok, tokens} <- Lexer.lex(test_input),
         {:ok, syntax} <- Parser.parse(tokens) do
      assert Generator.generate(syntax) == {:error, 7, {:undefined_symbol, "undefined"}}
    else
      error -> flunk("Got error: #{inspect(error)}")
    end
  end

  test "no-op directives" do
    inputs = [
      """
      .ifdef undefined
      .err
      .endif
      """,
      """
      .skip 0
      """,
      """
      .rept 0
      .err
      .endr
      """
    ]

    for input <- inputs do
      with {:ok, tokens} <- Lexer.lex(input),
           {:ok, syntax} <- Parser.parse(tokens),
           {:ok, rom} <- Generator.generate(syntax, 1) do
        assert rom == <<0::8>>
      else
        error -> flunk("Got error: #{inspect(error)}")
      end
    end
  end

  test "macros" do
    macros = """
    .macro test1 x, y=2
    .word \\x + \\y
    .endm
    
    .macro test2 x=2+1, y
    .if \\x == \\y
    .exitm
    .endif
    .word \\x * \\y
    .endm
    
    .macro collatz n, l=0
    .if \\n != 1
    .if \\n % 2 != 0
    collatz (3 * \\n) + 1, \\l + 1
    .else
    collatz \\n / 2, \\l + 1
    .endif
    .else
    .word \\l
    .endif
    .endm
    """

    tests = [
      {"test1 1", 3},
      {"test1 2,", 4},
      {"test1 3, 4", 7},
      {"test2 ,2", 6},
      {"test2 3, 4", 12},
      {"test2 5, 5", 0},
      {"collatz 27", 111}
    ]

    for {input, expected} <- tests do
      with {:ok, tokens} <- Lexer.lex(macros <> input),
           {:ok, syntax} <- Parser.parse(tokens),
           {:ok, rom} <- Generator.generate(syntax, 1) do
        assert rom == <<expected::8>>
      else
        error -> flunk("Got error: #{inspect(error)}")
      end
    end
  end

  test "macro errors" do
    tests = [
      {"""
       .irp x, 0, 0, 1
       .if \\x
       .exitm
       .endif
       .endr
       """, {3, :unexpected_exit_macro}},
      {"""
       .macro test x, y=1
       .endm
       test ,1
       """, {3, {:missing_required_argument, "test", "x"}}},
      {"""
       .macro maybe_err flag
       .if \\flag
       .err
       .endif
       .endm
       maybe_err 0
       maybe_err 1
       """, {[line: 3, macro_line: 7], :err_directive}},
      {"""
       .macro test x, y
       .endm
       test ,,
       """, {3, {:too_many_arguments, "test", 2, 3}}},
      {"""
       .macro test x, y, z
       .word \\x
       .endm
       test 1, 2, 3
       .word \\x
       """, {5, {:undefined_symbol, "\\x"}}}
    ]

    for {input, {line, expected_error}} <- tests do
      with {:ok, tokens} <- Lexer.lex(input),
           {:ok, syntax} <- Parser.parse(tokens) do
        assert Generator.generate(syntax) == {:error, line, expected_error}
      else
        error -> flunk("Got error: #{inspect(error)}")
      end
    end
  end

  test "bad calls" do
    tests = [
      {"""
       xyzzy 1, 2
       """, {:unknown_opcode, "xyzzy"}},
      {"""
       SKIP 1, 2, 3
       """, {:bad_opcode, "SKIP", 3}},
      {"""
       ADD ,
       """, {:missing_opcode_argument, "ADD"}}
    ]

    for {input, expected_error} <- tests do
      with {:ok, tokens} <- Lexer.lex(input),
           {:ok, syntax} <- Parser.parse(tokens) do
        assert Generator.generate(syntax) == {:error, 1, expected_error}
      else
        error -> flunk("Got error: #{inspect(error)}")
      end
    end
  end
end
