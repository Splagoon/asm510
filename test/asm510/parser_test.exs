defmodule ASM510.ParserTest do
  use ExUnit.Case

  test "unexpected token" do
    for test_tokens <- [
          # :
          [{{:separator, ?:}, 1}, {:eol, 1}],
          # call ,
          [{{:identifier, "call"}, 1}, {{:separator, ?,}, 1}, {:eol, 1}],
          # call 1,
          [{{:identifier, "call"}, 1}, {{:number, 1}, 1}, {{:separator, ?,}, 1}, {:eol, 1}]
        ] do
      syntax = ASM510.Parser.parse(test_tokens)

      assert match?({:error, 1, {:unexpected_token, _}}, syntax)
    end
  end

  test "call with args" do
    # call 1, name, 2
    test_tokens = [
      {{:identifier, "call"}, 1},
      {{:number, 1}, 1},
      {{:separator, ?,}, 1},
      {{:identifier, "name"}, 1},
      {{:separator, ?,}, 1},
      {{:number, 2}, 1},
      {:eol, 1}
    ]

    syntax = ASM510.Parser.parse(test_tokens)
    assert syntax == {:ok, [{{:call, "call", [number: 1, name: "name", number: 2]}, 1}]}
  end
end
