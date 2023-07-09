defmodule ASM510.Lexer do
  def lex(input) do
    input
    # Split on newlines
    |> String.split(~r/\R/)
    |> then(&scan(&1, 1, []))
  end

  defguardp is_nonzero_digit(c) when c in ?1..?9

  defguardp is_digit(c) when is_nonzero_digit(c) or c == ?0

  defguardp is_valid_identifier_start(c)
            when c in ?A..?Z or c in ?a..?z or c in ~c[$_.]

  defguardp is_valid_identifier(c) when is_valid_identifier_start(c) or is_digit(c)

  defguardp is_whitespace(c) when c in ~c[\s\t]

  defguardp is_separator(c) when c in ~c[,:]

  defguardp is_operator(c) when c in ~c[+-*/()<>%~|&^!]

  defp scan([], _, tokens), do: {:ok, Enum.reverse(tokens)}

  defp scan(["" | remaining_lines], line_number, tokens),
    do: scan(remaining_lines, line_number + 1, [{:eol, line_number} | tokens])

  defp scan([current_line | remaining_lines], line_number, tokens) do
    case current_line do
      # Whitespace
      <<c::utf8>> <> remaining_string when is_whitespace(c) ->
        scan([remaining_string | remaining_lines], line_number, tokens)

      # Colon
      <<c::utf8>> <> remaining_string when is_separator(c) ->
        scan([remaining_string | remaining_lines], line_number, [
          {{:separator, c}, line_number} | tokens
        ])

      # Comment
      "#" <> _ ->
        scan(["" | remaining_lines], line_number, tokens)

      # 2-char left shift
      "<<" <> remaining_string ->
        {:ok, token} = operator_to_token(?<, line_number)

        scan([remaining_string | remaining_lines], line_number, [
          {token, line_number} | tokens
        ])

      # 2-char right shift
      ">>" <> remaining_string ->
        {:ok, token} = operator_to_token(?>, line_number)

        scan([remaining_string | remaining_lines], line_number, [
          {token, line_number} | tokens
        ])

      # 1-char expression operators
      <<c::utf8>> <> remaining_string when is_operator(c) ->
        with {:ok, token} <- operator_to_token(c, line_number) do
          scan([remaining_string | remaining_lines], line_number, [
            {token, line_number} | tokens
          ])
        end

      # Hexadecimal number
      "0x" <> remaining_string ->
        with {:ok, number, new_remaining_string} <-
               scan_number(remaining_string, line_number, 16) do
          scan([new_remaining_string | remaining_lines], line_number, [
            {{:number, number}, line_number} | tokens
          ])
        end

      # Octal number
      "0" <> _ ->
        with {:ok, number, new_remaining_string} <- scan_number(current_line, line_number, 8) do
          scan([new_remaining_string | remaining_lines], line_number, [
            {{:number, number}, line_number} | tokens
          ])
        end

      # Decimal number
      <<c::utf8>> <> _ when is_nonzero_digit(c) ->
        with {:ok, number, new_remaining_string} <- scan_number(current_line, line_number, 10) do
          scan([new_remaining_string | remaining_lines], line_number, [
            {{:number, number}, line_number} | tokens
          ])
        end

      # Identifier
      <<c::utf8>> <> _ when is_valid_identifier_start(c) ->
        with {:ok, identifier, new_remaining_string} <- scan_identifier(current_line, line_number) do
          scan([new_remaining_string | remaining_lines], line_number, [
            {{:identifier, identifier}, line_number} | tokens
          ])
        end
    end
  end

  defp scan_identifier(string, line_number) do
    {identifier, remaining_string} = String.split_at(string, count_until_separator(string, 0))

    if String.length(identifier) > 0 and
         identifier |> String.to_charlist() |> Enum.all?(&is_valid_identifier/1) do
      {:ok, identifier, remaining_string}
    else
      {:error, line_number, {:bad_identifier, identifier}}
    end
  end

  defp scan_number(string, line_number, base) do
    {value_str, remaining_string} = String.split_at(string, count_until_separator(string, 0))

    with _ when value_str != "" <- value_str,
         {value, ""} <- Integer.parse(value_str, base) do
      {:ok, value, remaining_string}
    else
      _ -> {:error, line_number, {:bad_number, value_str}}
    end
  end

  defp count_until_separator("", count), do: count

  defp count_until_separator(<<c::utf8>> <> remaining_string, count) do
    if is_whitespace(c) or is_separator(c) do
      count
    else
      count_until_separator(remaining_string, count + 1)
    end
  end

  @operator_token_map %{
    ?+ => :plus,
    ?- => :minus,
    ?* => :multiply,
    ?/ => :divide,
    ?( => :open_paren,
    ?) => :close_paren,
    ?< => :left_shift,
    ?> => :right_shift,
    ?% => :modulo,
    ?~ => :complement,
    ?| => :or,
    ?& => :and,
    ?^ => :xor,
    ?! => :nor
  }
  defp operator_to_token(c, line_number) do
    with {:ok, operator} <- Map.fetch(@operator_token_map, c) do
      {:ok, {:operator, operator}}
    else
      :error -> {:error, line_number, {:unknown_operator, c}}
    end
  end

  def token_to_string(:eol), do: "EOL"
  def token_to_string({:separator, c}), do: "Separator \"#{to_string([c])}\""
  def token_to_string({:identifier, name}), do: "Identifier \"#{name}\""
  def token_to_string({:number, value}), do: "Number \"#{value}\""

  def token_to_string({:operator, operator}) do
    c =
      @operator_token_map
      |> Enum.find(fn {_, val} -> val == operator end)
      |> elem(0)

    "Operator: #{to_string([c])}"
  end

  def token_to_string(token), do: "Unknown token \"#{inspect(token)}\""
end
