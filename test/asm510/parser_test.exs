defmodule ASM510.ParserTest do
  use ExUnit.Case

  alias ASM510.{Lexer, Parser}

  test "unexpected token" do
    # :
    test_tokens = [{{:separator, ?:}, 1}, {:eol, 1}]

    syntax = Parser.parse(test_tokens)

    assert match?({:error, 1, {:unexpected_token, {:separator, ?:}}}, syntax)
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
                    {:identifier, "name"},
                    {:expression, [number: 2]}
                  ]}, 1}
              ]}
  end

  test "call with optional args" do
    # call ,,
    test_tokens =
      [
        {:identifier, "call"},
        {:separator, ?,},
        {:separator, ?,},
        :eol
      ]
      |> Enum.map(&{&1, 1})

    syntax = Parser.parse(test_tokens)

    assert syntax ==
             {:ok, [{{:call, "call", [nil, nil, nil]}, 1}]}
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
               {{:irp, {:identifier, "x"},
                 [
                   expression: [number: 2],
                   expression: [number: 3],
                   expression: [number: 4]
                 ],
                 [
                   {{:irp, {:identifier, "y"},
                     [
                       expression: [number: 5],
                       expression: [number: 6],
                       expression: [number: 7]
                     ],
                     [
                       {{:word, {:identifier, "\\x"}}, 4},
                       {{:word, {:identifier, "\\y"}}, 5}
                     ]}, 3},
                   {{:word, {:expression, [number: 8]}}, 7}
                 ]}, 2}
             ]
    else
      error -> flunk("Got error: #{inspect(error)}")
    end
  end

  test "declare reserved name" do
    test_input = """
    .set .test, 0
    """

    with {:ok, tokens} <- Lexer.lex(test_input) do
      assert Parser.parse(tokens) == {:error, 1, {:reserved_name, ".test"}}
    else
      error -> flunk("Got error: #{inspect(error)}")
    end
  end

  test "invalid variable name" do
    test_input = """
    .irp 1 + 1, 2
    """

    with {:ok, tokens} <- Lexer.lex(test_input) do
      assert Parser.parse(tokens) == {:error, 1, :expected_name}
    else
      error -> flunk("Got error: #{inspect(error)}")
    end
  end

  test "invalid directive" do
    test_tokens = [{{:identifier, ".xyzzy"}, 1}, {:eol, 1}]

    assert Parser.parse(test_tokens) == {:error, 1, {:invalid_directive, "xyzzy"}}
  end

  test "unclosed loop" do
    test_input = """
    .irp x, 1
    .word \\x
    """

    with {:ok, tokens} <- Lexer.lex(test_input) do
      assert Parser.parse(tokens) == {:error, 1, {:scope_not_closed, :loop}}
    else
      error -> flunk("Got error: #{inspect(error)}")
    end
  end

  test "if directive" do
    test_input = """
    .if 1
    .word 1
    .endif
    """

    with {:ok, tokens} <- Lexer.lex(test_input) do
      assert Parser.parse(tokens) ==
               {:ok,
                [
                  {{:if, {:expression, [number: 1]}, [{{:word, {:expression, [number: 1]}}, 2}],
                    nil}, 1}
                ]}
    end
  end

  test "if/else directives" do
    test_input = """
    .if 1
    .word 1
    .else
    .word 0
    .endif
    """

    with {:ok, tokens} <- Lexer.lex(test_input) do
      assert Parser.parse(tokens) ==
               {:ok,
                [
                  {{:if, {:expression, [number: 1]}, [{{:word, {:expression, [number: 1]}}, 2}],
                    [{{:word, {:expression, [number: 0]}}, 4}]}, 1}
                ]}
    end
  end

  test "scope not closed" do
    inputs = [
      {"""
       .if 1
       .word 1
       """, :if},
      {"""
       .ifndef foo
       .err
       .else
       .err
       """, :else},
      {"""
       .rept 3
       .word 3
       """, :loop},
      {"""
       .irp x, 4, 5
       .if \\x - 4
       .skip 1
       .endif
       .word \\x
       """, :loop}
    ]

    for {input, scope} <- inputs do
      with {:ok, tokens} <- Lexer.lex(input) do
        assert Parser.parse(tokens) == {:error, 1, {:scope_not_closed, scope}}
      else
        error -> flunk("Got error: #{inspect(error)}")
      end
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
    .xyzzy
    .endr
    .endr
    .endif
    .endif
    """

    with {:ok, tokens} <- Lexer.lex(test_input) do
      assert Parser.parse(tokens) == {:error, 7, {:invalid_directive, "xyzzy"}}
    else
      error -> flunk("Got error: #{inspect(error)}")
    end
  end

  test "macro definition" do
    tests = [
      {
        """
        .macro test arg1=x, arg2, arg3=3
        .word \\arg2
        .endm
        """,
        [
          {{:macro, "test",
            [
              {"arg1", {:identifier, "x"}},
              {"arg2", nil},
              {"arg3", {:expression, [number: 3]}}
            ],
            [
              {{:word, {:identifier, "\\arg2"}}, 2}
            ]}, 1}
        ]
      },
      {
        """
        .macro no_args
        .endm
        """,
        [{{:macro, "no_args", [], []}, 1}]
      },
      {
        """
        .macro one_arg the_arg
        .endm
        """,
        [{{:macro, "one_arg", [{"the_arg", nil}], []}, 1}]
      }
    ]

    for {input, expected_syntax} <- tests do
      with {:ok, tokens} <- Lexer.lex(input) do
        assert Parser.parse(tokens) == {:ok, expected_syntax}
      else
        error -> flunk("Got error: #{inspect(error)}")
      end
    end
  end

  test "bad macro definition" do
    tests = [
      {"""
       .macro 1
       """, {:unexpected_token, {:number, 1}}},
      {"""
       .macro test a,
       """, {:unexpected_token, :eol}},
      {"""
       .macro test 1
       """, {:unexpected_token, {:number, 1}}},
      {"""
       .macro test x=,
       """, {:unexpected_token, {:separator, ?,}}},
      {"""
       .macro test x+
       """, {:unexpected_token, {:operator, :add}}}
    ]

    for {input, expected_error} <- tests do
      with {:ok, tokens} <- Lexer.lex(input) do
        assert Parser.parse(tokens) == {:error, 1, expected_error}
      end
    end
  end
end
