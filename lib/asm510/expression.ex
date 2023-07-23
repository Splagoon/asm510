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

  def evaluate(expression, line, variables), do: evaluate(expression, [], line, variables)

  defp evaluate([], [final_value], line, variables), do: get_value(final_value, line, variables)

  defp evaluate(
         [{:operator, operator} | remaining_stack],
         [operand | remaining_arguments],
         line,
         variables
       )
       when is_unary(operator) do
    with {:ok, operand} <- get_value(operand, line, variables),
         operation <- get_operation(operator) do
      result = operation.(operand)
      evaluate(remaining_stack, [{:number, result} | remaining_arguments], line, variables)
    end
  end

  defp evaluate(
         [{:operator, operator} | remaining_stack],
         [rhs, lhs | remaining_arguments],
         line,
         variables
       )
       when not is_unary(operator) do
    with {:ok, lhs_value} <- get_value(lhs, line, variables),
         {:ok, rhs_value} <- get_value(rhs, line, variables),
         operation <- get_operation(operator) do
      result = operation.(lhs_value, rhs_value)
      evaluate(remaining_stack, [{:number, result} | remaining_arguments], line, variables)
    end
  end

  defp evaluate([token | remaining_stack], argument_stack, line, variables),
    do: evaluate(remaining_stack, [token | argument_stack], line, variables)

  defp evaluate(_, _, line, _), do: {:error, line, :invalid_expression}

  defp get_value({:number, value}, _, _), do: {:ok, value}

  defp get_value({:identifier, name}, line, variables) do
    with {:ok, value} <- Map.fetch(variables, name) do
      {:ok, value}
    else
      :error -> {:error, line, {:undefined_symbol, name}}
    end
  end

  defguardp is_operand(token) when token in [:number, :identifier]

  # parse_expression assumes the input tokens are in the expected grammar
  defp validate_operand([{operand, line} | remaining_tokens = [_ | _]], paren_depth) do
    case operand do
      {:operator, :open_paren} ->
        validate_operand(remaining_tokens, paren_depth + 1)

      {:operator, :close_paren} ->
        if paren_depth > 0 do
          validate_operator(remaining_tokens, paren_depth - 1)
        else
          {:error, line, {:unexpected_token, operand}}
        end

      {:operator, operator} when is_unary(operator) ->
        validate_operand(remaining_tokens, paren_depth)

      {token, _} when is_operand(token) ->
        validate_operator(remaining_tokens, paren_depth)

      _ ->
        {:error, line, {:unexpected_token, operand}}
    end
  end

  defp validate_operand([{last_token, line}], paren_depth) do
    case last_token do
      {token, _} when is_operand(token) and paren_depth == 0 ->
        :ok

      {:operator, :close_paren} when paren_depth == 1 ->
        :ok

      _ ->
        {:error, line, {:unexpected_token, last_token}}
    end
  end

  defp validate_operator([{operator, line} | remaining_tokens = [_ | _]], paren_depth) do
    case operator do
      {:operator, :close_paren} ->
        if paren_depth > 0 do
          validate_operator(remaining_tokens, paren_depth - 1)
        else
          {:error, line, {:unexpected_token, operator}}
        end

      {:operator, operator} when operator != :open_paren ->
        validate_operand(remaining_tokens, paren_depth)

      _ ->
        {:error, line, {:unexpected_token, operator}}
    end
  end

  defp validate_operator([{{:operator, :close_paren}, _}], 1), do: :ok

  defp validate_operator([{last_token, line}], _),
    do: {:error, line, {:unexpected_token, last_token}}

  def parse(tokens) do
    with :ok <- validate_operand(tokens, 0) do
      parse_expression(tokens, [], [])
    end
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
