defmodule ASM510.Lexer do
  def lex(input, file_name \\ nil) do
    input
    # Split on newlines
    |> String.split(~r/\R/)
    |> then(&scan(&1, %{file: file_name, line: 1}, []))
  end

  defguardp is_nonzero_digit(c) when c in ?1..?9

  defguardp is_digit(c) when is_nonzero_digit(c) or c == ?0

  defguardp is_letter(c) when c in ?A..?Z or c in ?a..?z

  defguardp is_valid_identifier_start(c)
            when is_letter(c) or c in ~c[$_.\\]

  defguardp is_valid_identifier(c) when is_letter(c) or is_digit(c) or c == ?_

  defguardp is_whitespace(c) when c in ~c[\s\t]

  defguardp is_separator(c) when c in ~c[,:="]

  defguardp is_operator(str)
            when str in [
                   ~c"<<",
                   ~c">>",
                   ~c"==",
                   ~c"!=",
                   ~c"<=",
                   ~c">=",
                   ~c"+",
                   ~c"*",
                   ~c"/",
                   ~c"(",
                   ~c")",
                   ~c"<",
                   ~c">",
                   ~c"%",
                   ~c"~",
                   ~c"|",
                   ~c"&",
                   ~c"^",
                   ~c"!",
                   ~c"-"
                 ]

  defp scan([], _, tokens), do: {:ok, Enum.reverse(tokens)}

  defp scan(["" | remaining_lines], location, tokens),
    do: scan(remaining_lines, %{location | line: location.line + 1}, [{:eol, location} | tokens])

  defp scan([current_line | remaining_lines], location, tokens) do
    case current_line do
      # Whitespace
      <<c::utf8>> <> remaining_string when is_whitespace(c) ->
        scan([remaining_string | remaining_lines], location, tokens)

      # Comment
      "#" <> _ ->
        scan(["" | remaining_lines], location, tokens)

      # String
      "\"" <> remaining_string ->
        with {:ok, string_value, new_remaining_string} <- read_string(remaining_string, "") do
          token = {:string, string_value}
          scan([new_remaining_string | remaining_lines], location, [{token, location} | tokens])
        else
          {:error, error} -> {:error, location, error}
        end

      # 2-char expression operators
      <<c1::utf8, c2::utf8>> <> remaining_string when is_operator([c1, c2]) ->
        with {:ok, token} <- operator_to_token([c1, c2], location) do
          scan([remaining_string | remaining_lines], location, [
            {token, location} | tokens
          ])
        end

      # Minus can be unary (negation) or binary (subtraction)
      "-" <> remaining_string ->
        operator =
          case tokens do
            # First token => negate
            [] -> :negate
            # Previous token is an operator (except ")") => negate
            [{{:operator, operator}, _} | _] when operator != :close_paren -> :negate
            # Otherwise => subtraction
            _ -> :subtract
          end

        scan([remaining_string | remaining_lines], location, [
          {{:operator, operator}, location} | tokens
        ])

      # Other 1-char expression operators
      <<c::utf8>> <> remaining_string when is_operator([c]) ->
        with {:ok, token} <- operator_to_token([c], location) do
          scan([remaining_string | remaining_lines], location, [
            {token, location} | tokens
          ])
        end

      # Separators
      <<c::utf8>> <> remaining_string when is_separator(c) ->
        scan([remaining_string | remaining_lines], location, [
          {{:separator, c}, location} | tokens
        ])

      # Hexadecimal number
      "0x" <> remaining_string ->
        with {:ok, number, new_remaining_string} <-
               scan_number(remaining_string, location, 16) do
          scan([new_remaining_string | remaining_lines], location, [
            {{:number, number}, location} | tokens
          ])
        end

      # Octal number
      "0" <> _ ->
        with {:ok, number, new_remaining_string} <- scan_number(current_line, location, 8) do
          scan([new_remaining_string | remaining_lines], location, [
            {{:number, number}, location} | tokens
          ])
        end

      # Decimal number
      <<c::utf8>> <> _ when is_nonzero_digit(c) ->
        with {:ok, number, new_remaining_string} <- scan_number(current_line, location, 10) do
          scan([new_remaining_string | remaining_lines], location, [
            {{:number, number}, location} | tokens
          ])
        end

      # Quoted identifier
      "'" <> <<c::utf8>> <> _ when is_valid_identifier_start(c) ->
        with {:ok, identifier, new_remaining_string} <-
               scan_identifier(String.slice(current_line, 1..-1), location) do
          scan([new_remaining_string | remaining_lines], location, [
            {{:quoted_identifier, identifier}, location} | tokens
          ])
        end

      # Identifier
      <<c::utf8>> <> _ when is_valid_identifier_start(c) ->
        with {:ok, identifier, new_remaining_string} <- scan_identifier(current_line, location) do
          scan([new_remaining_string | remaining_lines], location, [
            {{:identifier, identifier}, location} | tokens
          ])
        end
    end
  end

  defp scan_identifier(string, location) do
    {identifier, remaining_string} = String.split_at(string, count_until_separator(string, 0))

    # \@ is a special case
    if identifier == "\\@" or
         (String.length(identifier) > 0 and
            identifier
            |> String.to_charlist()
            |> then(fn [head | tail] ->
              is_valid_identifier_start(head) and Enum.all?(tail, &is_valid_identifier/1)
            end)) do
      {:ok, identifier, remaining_string}
    else
      {:error, location, {:bad_identifier, identifier}}
    end
  end

  defp scan_number(string, location, base) do
    {value_str, remaining_string} = String.split_at(string, count_until_separator(string, 0))

    with _ when value_str != "" <- value_str,
         {value, ""} <- Integer.parse(value_str, base) do
      {:ok, value, remaining_string}
    else
      _ -> {:error, location, {:bad_number, value_str}}
    end
  end

  defp count_until_separator("", count), do: count

  defp count_until_separator(<<c::utf8>> <> remaining_string, count) do
    if is_whitespace(c) or is_separator(c) or is_operator([c]) or (count > 0 and c in [?\\, ?']) do
      count
    else
      count_until_separator(remaining_string, count + 1)
    end
  end

  defp read_string("", _), do: {:error, :missing_end_quote}

  # escaped quote
  defp read_string("\\\"" <> remaining_string, string),
    do: read_string(remaining_string, string <> "\"")

  defp read_string(<<c::utf8>> <> remaining_string, string) do
    case c do
      ?" -> {:ok, string, remaining_string}
      _ -> read_string(remaining_string, string <> to_string([c]))
    end
  end

  @operator_token_map %{
    ~c"<<" => :left_shift,
    ~c">>" => :right_shift,
    ~c"==" => :equal,
    ~c"!=" => :not_equal,
    ~c"<=" => :less_or_equal,
    ~c">=" => :greater_or_equal,
    ~c"+" => :add,
    ~c"*" => :multiply,
    ~c"/" => :divide,
    ~c"(" => :open_paren,
    ~c")" => :close_paren,
    ~c"<" => :less_than,
    ~c">" => :greater_than,
    ~c"%" => :remainder,
    ~c"~" => :complement,
    ~c"|" => :or,
    ~c"&" => :and,
    ~c"^" => :xor,
    ~c"!" => :not
  }
  defp operator_to_token(c, location) do
    with {:ok, operator} <- Map.fetch(@operator_token_map, c) do
      {:ok, {:operator, operator}}
    else
      :error -> {:error, location, {:unknown_operator, c}}
    end
  end

  def token_to_string(:eol), do: "EOL"
  def token_to_string({:separator, c}), do: "Separator \"#{to_string([c])}\""
  def token_to_string({:identifier, name}), do: "Identifier \"#{name}\""
  def token_to_string({:number, value}), do: "Number \"#{value}\""
  def token_to_string({:string, value}), do: "String \"#{value}\""

  def token_to_string({:operator, operator}) do
    c =
      case operator do
        _ when operator in [:subtract, :negate] ->
          ?-

        _ ->
          @operator_token_map
          |> Enum.find(fn {_, val} -> val == operator end)
          |> elem(0)
      end

    "Operator: #{to_string([c])}"
  end

  def token_to_string(token), do: "Unknown token \"#{inspect(token)}\""
end
