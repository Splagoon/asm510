defmodule ASM510.Parser do
  alias ASM510.Expression

  def parse(tokens) do
    parse_line(tokens, [])
  end

  defp parse_line([], syntax), do: {:ok, Enum.reverse(syntax)}

  defp parse_line(tokens, syntax) do
    case tokens do
      # Empty line
      [{:eol, _} | remaining_tokens] ->
        parse_line(remaining_tokens, syntax)

      # Labels
      [
        {{:identifier, label_name}, line},
        {{:separator, ?:}, line},
        {:eol, line} | remaining_tokens
      ] ->
        parse_line(remaining_tokens, [{{:label, label_name}, line} | syntax])

      # Calls
      [{{:identifier, opcode}, line} | remaining_tokens] ->
        with {:ok, args, new_remaining_tokens} <- parse_call_args(remaining_tokens, []) do
          parse_line(new_remaining_tokens, [{{:call, opcode, args}, line} | syntax])
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
        {expression_tokens, [separator_token | remaining_tokens]} =
          Enum.split_while(tokens, fn {t, _} ->
            t not in [:eol, {:separator, ?,}]
          end)

        with {:ok, expression} <- Expression.parse(expression_tokens) do
          new_args = [{:expression, expression} | args]

          case separator_token do
            # Last arg
            {:eol, _} -> {:ok, Enum.reverse(new_args), remaining_tokens}
            # Another arg
            {{:separator, ?,}, _} -> parse_call_args(remaining_tokens, new_args)
          end
        end
    end
  end
end
