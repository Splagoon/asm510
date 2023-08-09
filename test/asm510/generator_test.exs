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
    inputs = [{".err", nil}, {".err \"foo\"", "foo"}]

    for {test_input, expected_message} <- inputs do
      with {:ok, tokens} <- Lexer.lex(test_input),
           {:ok, syntax} <- Parser.parse(tokens) do
        assert Generator.generate(syntax) ==
                 {:error, %{line: 1, file: nil}, {:err_directive, expected_message}}
      else
        error -> flunk("Got error: #{inspect(error)}")
      end
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
      assert Generator.generate(syntax) ==
               {:error, %{line: 7, file: nil}, {:undefined_symbol, "undefined"}}
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
    line = fn n -> %{line: n, file: nil} end

    tests = [
      {"""
       .irp x, 0, 0, 1
       .if \\x
       .exitm
       .endif
       .endr
       """, {line.(3), :unexpected_exit_macro}},
      {"""
       .macro test x, y=1
       .endm
       test ,1
       """, {line.(3), {:missing_required_argument, "test", "x"}}},
      {"""
       .macro maybe_err flag
       .if \\flag
       .err "\\flag is truthy"
       .endif
       .endm
       maybe_err 0
       maybe_err 1
       """, {Map.put(line.(3), :macro, line.(7)), {:err_directive, "\\flag is truthy"}}},
      {"""
       .macro test x, y
       .endm
       test ,,
       """, {line.(3), {:too_many_arguments, "test", 2, 3}}},
      {"""
       .macro test x, y, z
       .word \\x
       .endm
       test 1, 2, 3
       .word \\x
       """, {line.(5), {:undefined_symbol, "\\x"}}}
    ]

    for {input, {location, expected_error}} <- tests do
      with {:ok, tokens} <- Lexer.lex(input),
           {:ok, syntax} <- Parser.parse(tokens) do
        assert Generator.generate(syntax) == {:error, location, expected_error}
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
        assert Generator.generate(syntax) == {:error, %{line: 1, file: nil}, expected_error}
      else
        error -> flunk("Got error: #{inspect(error)}")
      end
    end
  end

  test "variables/labels in scopes" do
    tests = [
      {"""
       .ifndef X
       .set X, 0x0C
       .endif
       .word X
       """, 0x0C},
      {"""
       .macro test
       .org 0x10
       label:
       SKIP
       .endm
       .ifdef label
       .err
       .endif
       test
       .org 0
       .word label
       """, 0x10}
    ]

    for {input, expected} <- tests do
      with {:ok, tokens} <- Lexer.lex(input),
           {:ok, syntax} <- Parser.parse(tokens),
           {:ok, rom} <- Generator.generate(syntax, 1) do
        assert rom == <<expected::8>>
      else
        error -> flunk("Got error: #{inspect(error)}")
      end
    end
  end

  test "quoted symbols" do
    tests = [
      {"""
       .macro test_set name
       .ifdef 'name
       .err
       .endif
       .set 'name, 0x3D
       .endm
       test_set x
       .word x
       """, 0x3D},
      {"""
       .macro copy_to from, to
       .set 'to, \\from
       .endm
       .set x, 0x2F
       copy_to x, y
       .word y
       """, 0x2F},
      {"""
       .macro test1 x
       .set 'x, 3
       .endm
       .macro test2 x
       test1 'x
       .set 'x, \\x + 1
       .endm
       test2 asdf
       .word asdf
       """, 4},
      {"""
       .macro test n
       .org 15
       label_\\n:
       .endm
       test 3
       .org 0
       .word label_3
       """, 15},
      {"""
       .macro def_label name
       LABEL_'name:
       .endm
       def_label TEST
       .ifdef LABEL_TEST
       .word 94
       .else
       .err
       .endif
       """, 94}
    ]

    for {input, expected} <- tests do
      with {:ok, tokens} <- Lexer.lex(input),
           {:ok, syntax} <- Parser.parse(tokens),
           {:ok, rom} <- Generator.generate(syntax, 1) do
        assert rom == <<expected::8>>
      else
        error -> flunk("Got error: #{inspect(error)}")
      end
    end
  end

  test "quoted symbol errors" do
    line = fn n -> %{line: n, file: nil} end

    tests = [
      {"""
       .ifdef 'x
       .err
       .endif
       """, line.(1), {:undefined_symbol, "'x"}},
      {"""
       .macro test name
       .set 'name, \\name
       .endm
       test foo
       """, Map.put(line.(2), :macro, line.(4)), {:undefined_symbol, "foo"}},
      {"""
       .macro test
       .set 'asdf, 0
       .endm
       test
       """, Map.put(line.(2), :macro, line.(4)), {:undefined_symbol, "'asdf"}},
      {"""
       .macro test arg
       .set 'arg, 1
       .endm
       test x
       .set 'arg, 2
       """, line.(5), {:undefined_symbol, "'arg"}}
    ]

    for {input, line, error} <- tests do
      with {:ok, tokens} <- Lexer.lex(input),
           {:ok, syntax} <- Parser.parse(tokens) do
        assert Generator.generate(syntax, 1) == {:error, line, error}
      else
        error -> flunk("Got error: #{inspect(error)}")
      end
    end
  end

  test "undefined symbol in label expression" do
    line = fn n -> %{line: n, file: nil} end

    tests = [
      {"LABEL_\\value:", line.(1), "\\value"},
      {"LABEL_'name:", line.(1), "'name"},
      {"""
       .irp value, 1
       .word LABEL_\\value
       .endr
       """, line.(2), "LABEL_1"}
    ]

    for {input, location, symbol} <- tests do
      with {:ok, tokens} <- Lexer.lex(input),
           {:ok, syntax} <- Parser.parse(tokens) do
        assert Generator.generate(syntax, 1) == {:error, location, {:undefined_symbol, symbol}}
      else
        error -> flunk("Got error: #{inspect(error)}")
      end
    end
  end

  test "location counter variable" do
    test_input = """
    .org 0x1C
    .set here, .
    .org 0
    .word here
    """

    with {:ok, tokens} <- Lexer.lex(test_input),
         {:ok, syntax} <- Parser.parse(tokens),
         {:ok, rom} <- Generator.generate(syntax, 1) do
      assert rom == <<0x1C::8>>
    else
      error -> flunk("Got error: #{inspect(error)}")
    end
  end

  test "macro invocation counter" do
    test_input = """
    .macro macro1
    LABEL_\\@:
    .endm

    .macro macro2
    .set before, \\@
    LABEL_\\@:
    macro1
    .if before != \\@
    .err
    .endif
    .endm

    macro1 # 1
    macro1 # 2
    macro2 # 3, 4
    macro1 # 5

    .irp label, LABEL_0, LABEL_1, LABEL_2, LABEL_3, LABEL_4
    .ifndef \\label
    .err
    .endif
    .endr
    .ifdef \\@
    .err
    .endif
    """

    with {:ok, tokens} <- Lexer.lex(test_input),
         {:ok, syntax} <- Parser.parse(tokens),
         {:ok, rom} <- Generator.generate(syntax, 1) do
      assert rom == <<0::8>>
    else
      error -> flunk("Got error: #{inspect(error)}")
    end
  end

  test "fixups" do
    inputs = [
      {"""
       .word FUTURE_LABEL
       .org 0x41
       FUTURE_LABEL:
       """, 0x41},
      {"""
       .macro word_value n
       .word value_\\n
       .endm
       word_value 1
       .set value_1, 0x42
       """, 0x42}
    ]

    for {input, expected} <- inputs do
      with {:ok, tokens} <- Lexer.lex(input),
           {:ok, syntax} <- Parser.parse(tokens),
           {:ok, rom} <- Generator.generate(syntax, 1) do
        assert rom == <<expected::8>>
      else
        error -> flunk("Got error: #{inspect(error)}")
      end
    end
  end

  test "nested locations" do
    inputs = [
      {
        """
        .macro test1
        .irp x, 1, 2
        test2 \\x
        .endr
        .endm

        .macro test2 y
        .if \\y == 2
        test3
        .endif
        .endm

        .macro test3
        .rept 2
        .ifndef foo
        .set foo, 1
        .else
        .err "foo defined"
        .endif
        .endr
        .endm

        test1
        """,
        %{
          file: nil,
          line: 18,
          macro: %{
            file: nil,
            line: 9,
            macro: %{file: nil, line: 3, macro: %{line: 23, file: nil}}
          }
        }
      }
    ]

    for {test_input, expected_location} <- inputs do
      with {:ok, tokens} <- Lexer.lex(test_input),
           {:ok, syntax} <- Parser.parse(tokens) do
        assert Generator.generate(syntax) ==
                 {:error, expected_location, {:err_directive, "foo defined"}}
      else
        error -> flunk("Got error: #{inspect(error)}")
      end
    end
  end
end
