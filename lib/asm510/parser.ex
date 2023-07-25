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

      # Macro definitions are parsed differently than other directives
      [{{:identifier, ".macro"}, line} | remaining_tokens] ->
        with {:ok, name, args, new_remaining_tokens} <-
               parse_macro_args(remaining_tokens, nil, []),
             {:ok, macro_body, new_remaining_tokens} <-
               parse_line(new_remaining_tokens, [], :macro) do
          directive = {:macro, name, args, macro_body}
          parse_line(new_remaining_tokens, [{directive, line} | syntax], scope)
        end

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
      [{:eol, _} | remaining_tokens] ->
        case args do
          # No args
          [] ->
            {:ok, [], remaining_tokens}

          # If args is non-empty, then there was a trailing comma
          _ ->
            new_args = [nil | args]
            {:ok, Enum.reverse(new_args), remaining_tokens}
        end

      # Comma without expression (means this arg is default)
      [{{:separator, ?,}, _} | remaining_tokens] ->
        parse_call_args(remaining_tokens, [nil | args])

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

  defp parse_macro_args([{token, line} | remaining_tokens], nil, args) do
    # Macro name hasn't been parsed yet
    case token do
      {:identifier, name} ->
        parse_macro_args(remaining_tokens, name, args)

      _ ->
        {:error, line, {:unexpected_token, token}}
    end
  end

  defp parse_macro_args(tokens, name, args) do
    case tokens do
      # No args
      [{:eol, line} | remaining_tokens] ->
        case args do
          [] -> {:ok, name, [], remaining_tokens}
          # If args is non-empty, then there was a trailing comma
          _ -> {:error, line, {:unexpected_token, :eol}}
        end

      # Argument name
      [{{:identifier, arg_name}, _}, {next_token, line} | remaining_tokens] ->
        case next_token do
          {:separator, ?=} ->
            # Arg has a default value
            {expression_tokens, [{separator_token, line} | remaining_tokens]} =
              Enum.split_while(remaining_tokens, fn {t, _} ->
                t not in [:eol, {:separator, ?,}]
              end)

            if expression_tokens == [] do
              {:error, line, {:unexpected_token, separator_token}}
            else
              with {:ok, expression} <- Expression.parse(expression_tokens) do
                new_args = [{arg_name, {:expression, expression}} | args]

                case separator_token do
                  {:separator, ?,} ->
                    # Arg has default, another arg follows
                    parse_macro_args(remaining_tokens, name, new_args)

                  :eol ->
                    # Arg has default, last arg
                    {:ok, name, Enum.reverse(new_args), remaining_tokens}
                end
              end
            end

          {:separator, ?,} ->
            # Arg has no default, another arg follows
            new_args = [{arg_name, nil} | args]
            parse_macro_args(remaining_tokens, name, new_args)

          :eol ->
            # Arg has no default, last arg
            new_args = [{arg_name, nil} | args]
            {:ok, name, Enum.reverse(new_args), remaining_tokens}

          _ ->
            # Something else
            {:error, line, {:unexpected_token, next_token}}
        end

      # Something else
      [{token, line} | _] ->
        {:error, line, {:unexpected_token, token}}
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

  defp handle_directive("err", [], line, remaining_tokens, syntax, scope) do
    directive = :err
    parse_line(remaining_tokens, [{directive, line} | syntax], scope)
  end

  defp handle_directive("skip", [size], line, remaining_tokens, syntax, scope) do
    directive = {:skip, size, nil}
    parse_line(remaining_tokens, [{directive, line} | syntax], scope)
  end

  defp handle_directive("skip", [size, fill], line, remaining_tokens, syntax, scope) do
    directive = {:skip, size, fill}
    parse_line(remaining_tokens, [{directive, line} | syntax], scope)
  end

  defp handle_directive("rept", [count], line, remaining_tokens, syntax, scope) do
    with {:ok, loop_body, new_remaining_tokens} <- parse_line(remaining_tokens, [], :loop) do
      directive = {:rept, count, loop_body}
      parse_line(new_remaining_tokens, [{directive, line} | syntax], scope)
    else
      {:error, 0, {:scope_not_closed, :loop}} -> {:error, line, {:scope_not_closed, :loop}}
      error -> error
    end
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
      directive = {:irp, name, values, loop_body}
      parse_line(new_remaining_tokens, [{directive, line} | syntax], scope)
    else
      {:error, 0, {:scope_not_closed, :loop}} -> {:error, line, {:scope_not_closed, :loop}}
      error -> error
    end
  end

  defp handle_directive("endr", [], _, remaining_tokens, syntax, :loop),
    do: {:ok, Enum.reverse(syntax), remaining_tokens}

  defp handle_directive("if", [expression], line, remaining_tokens, syntax, scope),
    do: parse_if_else(remaining_tokens, expression, line, syntax, scope)

  defp handle_directive(
         "ifdef",
         [{:expression, [identifier: name]}],
         line,
         remaining_tokens,
         syntax,
         scope
       ),
       do: parse_if_else(remaining_tokens, {:defined?, name}, line, syntax, scope)

  defp handle_directive(
         "ifndef",
         [{:expression, [identifier: name]}],
         line,
         remaining_tokens,
         syntax,
         scope
       ),
       do: parse_if_else(remaining_tokens, {:not_defined?, name}, line, syntax, scope)

  defp handle_directive("else", [], _, remaining_tokens, syntax, :if),
    do: {:ok, Enum.reverse(syntax), remaining_tokens, :else}

  defp handle_directive("endif", [], _, remaining_tokens, syntax, scope)
       when scope in [:if, :else],
       do: {:ok, Enum.reverse(syntax), remaining_tokens, :endif}

  defp handle_directive("endm", [], _, remaining_tokens, syntax, :macro),
    do: {:ok, Enum.reverse(syntax), remaining_tokens}

  defp handle_directive("exitm", [], line, remaining_tokens, syntax, scope) do
    # .exitm needs to be carried forward into the generation phase, plus we
    # can't exit the current scope until we find .endm
    directive = :exit_macro
    parse_line(remaining_tokens, [{directive, line} | syntax], scope)
  end

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

  defp parse_if_else(remaining_tokens, condition, line, syntax, scope) do
    with {:ok, if_body, new_remaining_tokens, closer} <- parse_line(remaining_tokens, [], :if) do
      case closer do
        :endif ->
          parse_line(
            new_remaining_tokens,
            [{{:if, condition, if_body, nil}, line} | syntax],
            scope
          )

        :else ->
          with {:ok, else_body, new_remaining_tokens, :endif} <-
                 parse_line(new_remaining_tokens, [], :else) do
            parse_line(
              new_remaining_tokens,
              [
                {{:if, condition, if_body, else_body}, line} | syntax
              ],
              scope
            )
          else
            {:error, 0, {:scope_not_closed, :else}} ->
              {:error, line, {:scope_not_closed, :else}}

            error ->
              error
          end
      end
    else
      {:error, 0, {:scope_not_closed, :if}} ->
        {:error, line, {:scope_not_closed, :if}}

      error ->
        error
    end
  end

  def directive_to_close_scope(:loop), do: ".endr"
  def directive_to_close_scope(d) when d in [:if, :else], do: ".endif"
  def directive_to_close_scope(:macro), do: ".endm"
end
