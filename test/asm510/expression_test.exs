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
end
