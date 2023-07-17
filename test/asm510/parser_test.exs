defmodule ASM510.ParserTest do
  use ExUnit.Case

  alias ASM510.{Lexer, Parser}

  test "unexpected token" do
    for test_tokens <- [
          # :
          [{{:separator, ?:}, 1}, {:eol, 1}],
          # call ,
          [{{:identifier, "call"}, 1}, {{:separator, ?,}, 1}, {:eol, 1}],
          # call 1,
          [{{:identifier, "call"}, 1}, {{:number, 1}, 1}, {{:separator, ?,}, 1}, {:eol, 1}]
        ] do
      syntax = Parser.parse(test_tokens)

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

    syntax = Parser.parse(test_tokens)

    assert syntax ==
             {:ok,
              [
                {{:call, "call",
                  [
                    {:expression, [number: 1]},
                    {:expression, [identifier: "name"]},
                    {:expression, [number: 2]}
                  ]}, 1}
              ]}
  end

  test "nested loops" do
    test_input = """
    .word 1
    .irp x, 2, 3, 4
    .irp y, 5, 6, 7
    .word \\x
    .word \\y
    .endr
    .word 8
    .endr
    """

    with {:ok, tokens} <- Lexer.lex(test_input),
         {:ok, syntax} <- Parser.parse(tokens) do
      assert syntax == [
               {{:word, {:expression, [number: 1]}}, 1},
               {{:irp, "x",
                 [
                   expression: [number: 2],
                   expression: [number: 3],
                   expression: [number: 4]
                 ],
                 [
                   {{:irp, "y",
                     [
                       expression: [number: 5],
                       expression: [number: 6],
                       expression: [number: 7]
                     ],
                     [
                       {{:word, {:expression, [identifier: "\\x"]}}, 4},
                       {{:word, {:expression, [identifier: "\\y"]}}, 5}
                     ]}, 3},
                   {{:word, {:expression, [number: 8]}}, 7}
                 ]}, 2}
             ]
    else
      error -> flunk("Got error: #{inspect(error)}")
    end
  end
end
