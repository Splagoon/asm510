defmodule ASM510.Parser do
  alias ASM510.Expression

  def parse(tokens) do
    with {:ok, syntax, remaining_tokens} <- parse_line(tokens, [], nil) do
      case remaining_tokens do
        [] -> {:ok, syntax}
        [{token, line} | _] -> {:error, line, {:unexpected_token, token}}
      end
    end
  end

  defp parse_line([], syntax, nil), do: {:ok, Enum.reverse(syntax), []}

  defp parse_line([], _, scope), do: {:error, 0, {:scope_not_closed, scope}}

  defp parse_line(tokens, syntax, scope) do
    case tokens do
      # Empty line
      [{:eol, _} | remaining_tokens] ->
        parse_line(remaining_tokens, syntax, scope)

      # Labels
      [
        {{:identifier, label_name}, line},
        {{:separator, ?:}, line},
        {:eol, line} | remaining_tokens
      ] ->
        parse_line(remaining_tokens, [{{:label, label_name}, line} | syntax], scope)

      # Calls and directives
      [{{:identifier, opcode}, line} | remaining_tokens] ->
        with {:ok, args, new_remaining_tokens} <- parse_call_args(remaining_tokens, []) do
          case opcode do
            "." <> directive ->
              handle_directive(directive, args, line, new_remaining_tokens, syntax, scope)

            _ ->
              parse_line(new_remaining_tokens, [{{:call, opcode, args}, line} | syntax], scope)
          end
        end

      # Other
      [{token, line} | _] ->
        {:error, line, {:unexpected_token, token}}
    end
  end

  defp parse_call_args(tokens, args) do
    case tokens do
      # No args
      [token = {:eol, line} | remaining_tokens] ->
        case args do
          [] -> {:ok, [], remaining_tokens}
          # If args is non-empty, then there was a trailing comma
          _ -> {:error, line, {:unexpected_token, token}}
        end

      # Expression
      _ ->
        {expression_tokens, [{separator_token, line} | remaining_tokens]} =
          Enum.split_while(tokens, fn {t, _} ->
            t not in [:eol, {:separator, ?,}]
          end)

        if expression_tokens == [] do
          {:error, line, {:unexpected_token, separator_token}}
        else
          with {:ok, expression} <- Expression.parse(expression_tokens) do
            new_args = [{:expression, expression} | args]

            case separator_token do
              # Last arg
              :eol -> {:ok, Enum.reverse(new_args), remaining_tokens}
              # Another arg
              {:separator, ?,} -> parse_call_args(remaining_tokens, new_args)
            end
          end
        end
    end
  end

  defp handle_directive("word", [value], line, remaining_tokens, syntax, scope) do
    directive = {:word, value}
    parse_line(remaining_tokens, [{directive, line} | syntax], scope)
  end

  defp handle_directive(
         "set",
         [name, value],
         line,
         remaining_tokens,
         syntax,
         scope
       ) do
    with {:ok, name} <- get_variable_name(name, line) do
      directive = {:set, name, value}
      parse_line(remaining_tokens, [{directive, line} | syntax], scope)
    end
  end

  defp handle_directive("org", [value], line, remaining_tokens, syntax, scope) do
    directive = {:org, value}
    parse_line(remaining_tokens, [{directive, line} | syntax], scope)
  end

  defp handle_directive(
         "irp",
         [name | values],
         line,
         remaining_tokens,
         syntax,
         scope
       ) do
    with {:ok, name} <- get_variable_name(name, line),
         {:ok, loop_body, new_remaining_tokens} <-
           parse_line(remaining_tokens, [], :loop) do
      parse_line(new_remaining_tokens, [{{:irp, name, values, loop_body}, line} | syntax], scope)
    else
      {:error, 0, {:scope_not_closed, :loop}} -> {:error, line, {:scope_not_closed, :loop}}
      error -> error
    end
  end

  defp handle_directive("endr", [], _, remaining_tokens, syntax, :loop),
    do: {:ok, Enum.reverse(syntax), remaining_tokens}

  defp handle_directive(directive, _, line, _, _, _),
    do: {:error, line, {:invalid_directive, directive}}

  defp get_variable_name(expression, line) do
    case expression do
      {:expression, [identifier: name = <<c::utf8>> <> _]} ->
        if c not in ~c[.\\] do
          {:ok, name}
        else
          {:error, line, {:reserved_name, name}}
        end

      _ ->
        {:error, line, :expected_name}
    end
  end

  def directive_to_close_scope(:loop), do: ".endr"
end
