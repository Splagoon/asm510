defmodule ASM510.ExpressionTest do
  use ExUnit.Case

  alias ASM510.Expression

  test "arithmetic" do
    # 5 * 7 - 6 / -(3 - 5) + 9 + -1
    tokens =
      [
        {:number, 5},
        {:operator, :multiply},
        {:number, 7},
        {:operator, :subtract},
        {:number, 6},
        {:operator, :divide},
        {:operator, :negate},
        {:operator, :open_paren},
        {:number, 3},
        {:operator, :subtract},
        {:number, 5},
        {:operator, :close_paren},
        {:operator, :add},
        {:number, 9},
        {:operator, :add},
        {:operator, :negate},
        {:number, 1}
      ]
      |> Enum.map(&{&1, 1})

    with {:ok, expression} <- Expression.parse(tokens),
         {:ok, result} <- Expression.evaluate(expression, %{}) do
      assert result == 40
    else
      error -> flunk("Got error: #{inspect(error)}")
    end
  end

  test "RPN" do
    # 2 3 *
    tokens =
      [
        {:number, 2},
        {:number, 3},
        {:operator, :multiply}
      ]
      |> Enum.map(&{&1, 1})

    expression = Expression.parse(tokens)

    assert expression == {:error, 1, {:unexpected_token, {:number, 3}}}
  end

  test "empty parens" do
    # 1 () + 2
    tokens =
      [
        {:number, 1},
        {:operator, :open_paren},
        {:number, 3},
        {:operator, :add},
        {:operator, :close_paren},
        {:operator, :add},
        {:number, 2}
      ]
      |> Enum.map(&{&1, 1})

    expression = Expression.parse(tokens)

    assert expression == {:error, 1, {:unexpected_token, {:operator, :open_paren}}}
  end

  test "parens with constant expressions" do
    # (1) + ((2))
    tokens =
      [
        {:operator, :open_paren},
        {:number, 1},
        {:operator, :close_paren},
        {:operator, :add},
        {:operator, :open_paren},
        {:number, 2},
        {:operator, :close_paren}
      ]
      |> Enum.map(&{&1, 1})

    with {:ok, expression} <- Expression.parse(tokens),
         {:ok, result} <- Expression.evaluate(expression, %{}) do
      assert result == 3
    else
      error -> flunk("Got error: #{inspect(error)}")
    end
  end

  test "extra close paren" do
    # )2
    tokens =
      [{:operator, :close_paren}, {:number, 2}]
      |> Enum.map(&{&1, 1})

    expression = Expression.parse(tokens)

    assert expression == {:error, 1, {:unexpected_token, {:operator, :close_paren}}}
  end

  test "extra open paren" do
    # ((3)
    tokens =
      [
        {:operator, :open_paren},
        {:operator, :open_paren},
        {:number, 3},
        {:operator, :close_paren}
      ]
      |> Enum.map(&{&1, 1})

    expression = Expression.parse(tokens)

    assert expression == {:error, 1, {:unexpected_token, {:operator, :close_paren}}}
  end
end
