defmodule ASM510.LexerTest do
  use ExUnit.Case

  test "decimal number" do
    test_input = "2434"
    tokens = ASM510.Lexer.lex(test_input)
    assert tokens == {:ok, [{{:number, 2434}, 1}, {:eol, 1}]}
  end

  test "bad identifier" do
    test_input = "abc&"
    tokens = ASM510.Lexer.lex(test_input)
    assert tokens == {:error, 1, {:bad_identifier, "abc&"}}
  end

  test "bad number" do
    for test_input <- ["0x0x0", "0xtwo", "0x"] do
      tokens = ASM510.Lexer.lex(test_input)
      assert tokens == {:error, 1, {:bad_number, String.slice(test_input, 2..-1//1)}}
    end
  end

  test "operators" do
    test_input = "><<^>><"
    tokens = ASM510.Lexer.lex(test_input)

    assert tokens =
             {:ok,
              [
                {{:operator, :right_shift}, 1},
                {{:operator, :left_shift}, 1},
                {{:operator, :xor}, 1},
                {{:operator, :right_shift}, 1},
                {{:operator, :left_shift}, 1}
              ]}
  end
end