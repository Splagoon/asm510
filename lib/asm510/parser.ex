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

      # Macro definitions are parsed differently than other directives
      [{{:identifier, ".macro"}, line} | remaining_tokens] ->
        with {:ok, name, args, new_remaining_tokens} <-
               parse_macro_args(remaining_tokens, nil, []),
             {:ok, macro_body, new_remaining_tokens} <-
               parse_line(new_remaining_tokens, [], :macro) do
          directive = {:macro, name, args, macro_body}
          parse_line(new_remaining_tokens, [{directive, line} | syntax], scope)
        end

      # Labels, calls, and directives
      [{{:identifier, name}, line} | remaining_tokens] ->
        # First, try to parse a label
        with {:ok, label, new_remaining_tokens} <- parse_label(tokens) do
          parse_line(new_remaining_tokens, [{{:label, label}, line} | syntax], scope)
        else
          # If it's not a label, try again as a call or directive
          _ ->
            with {:ok, args, new_remaining_tokens} <- parse_call_args(remaining_tokens, []) do
              case name do
                "." <> directive ->
                  handle_directive(directive, args, line, new_remaining_tokens, syntax, scope)

                _ ->
                  parse_line(new_remaining_tokens, [{{:call, name, args}, line} | syntax], scope)
              end
            end
        end

      # Other
      [{token, line} | _] ->
        {:error, line, {:unexpected_token, token}}
    end
  end

  defp parse_label_expression(tokens) do
    non_identifier_token =
      Enum.find(
        tokens,
        &(not match?({{type, _}, _} when type in [:identifier, :quoted_identifier], &1))
      )

    case non_identifier_token do
      nil ->
        expression =
          tokens
          |> Enum.map(fn {token, _} ->
            case token do
              {:quoted_identifier, name} -> {:variable, "'#{name}"}
              {:identifier, "\\" <> name} -> {:variable, "\\#{name}"}
              {:identifier, name} -> {:constant, name}
            end
          end)

        {:ok, {:label_expression, expression}}

      {token, line} ->
        {:error, line, {:unexpected_token, token}}
    end
  end

  defp parse_arg(tokens) do
    case tokens do
      [{{:identifier, name}, _}] ->
        {:ok, {:identifier, name}}

      [{{:quoted_identifier, name}, _}] ->
        {:ok, {:quoted_identifier, name}}

      _ ->
        with {:ok, label} <- parse_label_expression(tokens) do
          {:ok, label}
        else
          _ -> Expression.parse(tokens)
        end
    end
  end

  defp parse_label(tokens) do
    {label_tokens, [{separator_token, line} | remaining_tokens]} =
      Enum.split_while(tokens, fn {t, _} ->
        t not in [:eol, {:separator, ?:}]
      end)

    with {:ok, label} <- parse_label_expression(label_tokens) do
      cond do
        separator_token != {:separator, ?:} or Enum.empty?(label_tokens) ->
          {:error, line, {:unexpected_token, separator_token}}

        true ->
          {:ok, label, remaining_tokens}
      end
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

        new_args =
          case expression_tokens do
            [] ->
              {:error, line, {:unexpected_token, separator_token}}

            _ ->
              with {:ok, arg} <- parse_arg(expression_tokens) do
                {:ok, [arg | args]}
              end
          end

        with {:ok, new_args} <- new_args do
          case separator_token do
            # Last arg
            :eol -> {:ok, Enum.reverse(new_args), remaining_tokens}
            # Another arg
            {:separator, ?,} -> parse_call_args(remaining_tokens, new_args)
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
              with {:ok, arg} <- parse_arg(expression_tokens) do
                new_args = [{arg_name, arg} | args]

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

  defp handle_directive("if", [expression], line, remaining_tokens, syntax, scope) do
    parse_if_else(remaining_tokens, expression, line, syntax, scope)
  end

  defp handle_directive(
         "ifdef",
         [{type, name}],
         line,
         remaining_tokens,
         syntax,
         scope
       )
       when type in [:identifier, :quoted_identifier],
       do:
         parse_if_else(
           remaining_tokens,
           {:defined?, {type, name}},
           line,
           syntax,
           scope
         )

  defp handle_directive(
         "ifndef",
         [{type, name}],
         line,
         remaining_tokens,
         syntax,
         scope
       )
       when type in [:identifier, :quoted_identifier],
       do:
         parse_if_else(
           remaining_tokens,
           {:not_defined?, {:identifier, name}},
           line,
           syntax,
           scope
         )

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
      {:identifier, name = <<c::utf8>> <> _} ->
        if c not in ~c[.\\] do
          {:ok, {:identifier, name}}
        else
          {:error, line, {:reserved_name, name}}
        end

      quoted_identifier = {:quoted_identifier, _} ->
        {:ok, quoted_identifier}

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
