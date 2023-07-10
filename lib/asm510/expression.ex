defmodule ASM510.Expression do
  import Bitwise

  defp get_operation(operator),
    do:
      %{
        :negate => &Kernel.-/1,
        :complement => &Bitwise.~~~/1,
        :add => &Kernel.+/2,
        :subtract => &Kernel.-/2,
        :multiply => &Kernel.*/2,
        :divide => &Kernel.div/2,
        :remainder => &Kernel.rem/2,
        :left_shift => &Bitwise.<<</2,
        :right_shift => &Bitwise.>>>/2,
        :or => &Bitwise.|||/2,
        :and => &Bitwise.&&&/2,
        :xor => &Bitwise.^^^/2,
        :or_not => &(&1 ||| ~~~&2)
      }[operator]

  defguardp is_unary(operator) when operator in [:negate, :complement]

  def evaluate(expression, variables), do: evaluate(expression, [], variables)

  defp evaluate([], [final_value], variables), do: get_value(final_value, variables)

  defp evaluate(
         [{:operator, operator} | remaining_stack],
         [operand | remaining_arguments],
         variables
       )
       when is_unary(operator) do
    with {:ok, operand} <- get_value(operand, variables),
         operation <- get_operation(operator) do
      result = operation.(operand)
      evaluate(remaining_stack, [{:number, result} | remaining_arguments], variables)
    end
  end

  defp evaluate(
         [{:operator, operator} | remaining_stack],
         [rhs, lhs | remaining_arguments],
         variables
       )
       when not is_unary(operator) do
    with {:ok, lhs_value} <- get_value(lhs, variables),
         {:ok, rhs_value} <- get_value(rhs, variables),
         operation <- get_operation(operator) do
      result = operation.(lhs_value, rhs_value)
      evaluate(remaining_stack, [{:number, result} | remaining_arguments], variables)
    end
  end

  defp evaluate([token | remaining_stack], argument_stack, variables),
    do: evaluate(remaining_stack, [token | argument_stack], variables)

  defp evaluate(_, _, _), do: {:error, :invalid_expression}

  defp get_value({:number, value}, _), do: {:ok, value}

  defp get_value({:identifier, name}, variables) do
    with {:ok, value} <- Map.fetch(variables, name) do
      {:ok, value}
    else
      :error -> {:error, {:undefined_symbol, name}}
    end
  end

  def parse(tokens) do
    parse_expression(tokens, [], [])
  end

  @precedence_map %{
    :add => 1,
    :subtract => 1,
    :or => 2,
    :and => 2,
    :xor => 2,
    :or_not => 2,
    :multiply => 3,
    :divide => 3,
    :remainder => 3,
    :left_shift => 3,
    :right_shift => 3,
    :negate => 9,
    :complement => 9
  }

  # https://en.wikipedia.org/wiki/Shunting-yard_algorithm
  defp parse_expression([{token, line} | remaining_tokens], output, op_stack) do
    case token do
      {t, _} when t in [:number, :identifier] ->
        parse_expression(remaining_tokens, [token | output], op_stack)

      {:operator, :open_paren} ->
        parse_expression(remaining_tokens, output, [token | op_stack])

      {:operator, :close_paren} ->
        {popped, [_ | new_op_stack]} =
          Enum.split_while(op_stack, &(&1 != {:operator, :open_paren}))

        new_output = Enum.reverse(popped) ++ output
        parse_expression(remaining_tokens, new_output, new_op_stack)

      {:operator, operator} when is_unary(operator) ->
        parse_expression(remaining_tokens, output, [token | op_stack])

      {:operator, operator} ->
        {popped, new_op_stack} =
          Enum.split_while(
            op_stack,
            fn {:operator, o} ->
              o !== :open_paren and @precedence_map[o] >= @precedence_map[operator]
            end
          )

        new_output = Enum.reverse(popped) ++ output
        parse_expression(remaining_tokens, new_output, [token | new_op_stack])

      _ ->
        {:error, line, {:unexpected_token, token}}
    end
  end

  defp parse_expression([], output, [op_head | op_stack]),
    do: parse_expression([], [op_head | output], op_stack)

  defp parse_expression([], output, []), do: {:ok, Enum.reverse(output)}
end
