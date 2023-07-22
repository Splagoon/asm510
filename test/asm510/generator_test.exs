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
    .set x, 0x00
    .else
    .set x, 0x12
    .endif
    .word x
    """

    input2 = """
    .ifndef x
    .set x, 0x12
    .else
    .set x, 0x00
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
end
