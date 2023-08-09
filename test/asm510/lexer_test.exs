defmodule ASM510.LexerTest do
  use ExUnit.Case

  test "decimal number" do
    test_input = "2434"
    l = %{file: nil, line: 1}
    tokens = ASM510.Lexer.lex(test_input)
    assert tokens == {:ok, [{{:number, 2434}, l}, {:eol, l}]}
  end

  test "bad identifier" do
    test_input = "abc$"
    l = %{file: nil, line: 1}
    tokens = ASM510.Lexer.lex(test_input)
    assert tokens == {:error, l, {:bad_identifier, "abc$"}}
  end

  test "bad number" do
    l = %{file: nil, line: 1}

    for test_input <- ["0x0x0", "0xtwo", "0x"] do
      tokens = ASM510.Lexer.lex(test_input)
      assert tokens == {:error, l, {:bad_number, String.slice(test_input, 2..-1//1)}}
    end
  end

  test "operators" do
    test_input = "><<^>><"
    l = %{file: nil, line: 1}
    tokens = ASM510.Lexer.lex(test_input)

    assert tokens ==
             {:ok,
              [
                {{:operator, :greater_than}, l},
                {{:operator, :left_shift}, l},
                {{:operator, :xor}, l},
                {{:operator, :right_shift}, l},
                {{:operator, :less_than}, l},
                {:eol, l}
              ]}
  end

  test "unary/binary minus" do
    test_input = "-2 - -1"
    l = %{file: nil, line: 1}
    tokens = ASM510.Lexer.lex(test_input)

    assert tokens ==
             {:ok,
              [
                {{:operator, :negate}, l},
                {{:number, 2}, l},
                {{:operator, :subtract}, l},
                {{:operator, :negate}, l},
                {{:number, 1}, l},
                {:eol, l}
              ]}
  end

  test "operators as separators" do
    test_input = "1+(0x10)"
    l = %{file: nil, line: 1}
    tokens = ASM510.Lexer.lex(test_input)

    assert tokens ==
             {:ok,
              [
                {{:number, 1}, l},
                {{:operator, :add}, l},
                {{:operator, :open_paren}, l},
                {{:number, 16}, l},
                {{:operator, :close_paren}, l},
                {:eol, l}
              ]}
  end

  test "string" do
    test_input = ".err \"got \\\"foo\\\", expected \\\"bar\\\"\""
    l = %{file: nil, line: 1}
    tokens = ASM510.Lexer.lex(test_input)

    assert tokens ==
             {:ok,
              [
                {{:identifier, ".err"}, l},
                {{:string, "got \"foo\", expected \"bar\""}, l},
                {:eol, l}
              ]}
  end

  test "invalid string" do
    test_input = ".include \"file"
    l = %{file: nil, line: 1}
    tokens = ASM510.Lexer.lex(test_input)

    assert tokens ==
             {:error, l, :missing_end_quote}
  end
end
