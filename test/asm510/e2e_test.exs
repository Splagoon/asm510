defmodule ASM510.E2ETest do
  use ExUnit.Case
  alias ASM510.{Lexer, Parser, Generator}

  setup do
    with {:ok, test_file} <- File.read("test/input/test.s") do
      {:ok, test_file: test_file}
    end
  end

  test "test file", %{test_file: test_file} do
    with {:ok, tokens} <- Lexer.lex(test_file),
         {:ok, syntax} <- Parser.parse(tokens),
         {:ok, data} <- Generator.generate(syntax) do
      hash = :crypto.hash(:sha3_224, data) |> Base.encode64()
      assert hash == "DnXwdGF6WtRgn10JXVgRkA5/El+VipjZP/nEmQ=="
    else
      error -> flunk("got error: #{inspect(error)}")
    end
  end
end
