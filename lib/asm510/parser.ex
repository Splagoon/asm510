defmodule ASM510.Parser do
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
        with {:ok, args, new_remaining_tokens} <- parse_call_args(remaining_tokens) do
          parse_line(new_remaining_tokens, [{{:call, opcode, args}, line} | syntax])
        end

      # Other
      [{token, line} | _] ->
        {:error, line, {:unexpected_token, token}}
    end
  end

  defp parse_call_args(tokens) do
    case tokens do
      # No args
      [{:eol, _} | remaining_tokens] ->
        {:ok, [], remaining_tokens}

      # Identifier
      [{{:identifier, name}, _} | remaining_tokens] ->
        parse_next_call_arg(remaining_tokens, [{:name, name}])

      # Number
      [{{:number, value}, _} | remaining_tokens] ->
        parse_next_call_arg(remaining_tokens, [{:number, value}])

      # Other
      [{token, line} | _] ->
        {:error, line, {:unexpected_token, token}}
    end
  end

  defp parse_next_call_arg(tokens, args) do
    case tokens do
      # No further arguments
      [{:eol, _} | remaining_tokens] ->
        {:ok, Enum.reverse(args), remaining_tokens}

      # Identifier
      [{{:separator, ?,}, _}, {{:identifier, name}, _} | remaining_tokens] ->
        parse_next_call_arg(remaining_tokens, [{:name, name} | args])

      # Number
      [{{:separator, ?,}, _}, {{:number, value}, _} | remaining_tokens] ->
        parse_next_call_arg(remaining_tokens, [{:number, value} | args])

      # Other
      [{token, line} | _] ->
        {:error, line, {:unexpected_token, token}}
    end
  end
end
