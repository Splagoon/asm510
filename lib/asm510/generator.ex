defmodule ASM510.Generator.State do
  defstruct pc: 0, env: %{}, macros: %{}, data: %{}
end

defmodule ASM510.Generator do
  import Bitwise

  alias ASM510.{Generator.State, Opcodes, Expression}
  require Opcodes

  def generate(syntax, rom_size \\ 4096) do
    with {:ok, state} <- generate_all(syntax, %State{}) do
      state.data
      |> assemble_rom(rom_size)
      |> then(&{:ok, &1})
    else
      {{:exit_macro, line}, _} -> {:error, line, :unexpected_exit_macro}
      error -> error
    end
  end

  defp assemble_rom(data, size) do
    for i <- 0..(size - 1) do
      Map.get(data, i, <<0::8>>)
    end
    |> IO.iodata_to_binary()
  end

  defp generate_all([], state), do: {:ok, state}

  defp generate_all([syntax | remaining_syntax], state) do
    with {:ok, state} <- generate_one(syntax, state) do
      generate_all(remaining_syntax, state)
    end
  end

  defp generate_one(syntax, state) do
    case syntax do
      {{:label, {:label_expression, label_expr}}, line} ->
        with {:ok, label_name} <- get_label_name(label_expr, line, state.env) do
          {:ok, %State{state | env: Map.put_new(state.env, label_name, state.pc)}}
        end

      {{:set, name, value_arg}, line} ->
        name = get_identifier_name(name, line, state.env)

        with {:ok, name} <- name,
             {:ok, value} <- get_arg_value(value_arg, line, state.env) do
          {:ok, %State{state | env: Map.put(state.env, name, value)}}
        end

      {{:org, value_arg}, line} ->
        with {:ok, value} <- get_arg_value(value_arg, line, state.env) do
          {:ok, %State{state | pc: value}}
        end

      {{:word, value_arg}, line} ->
        with {:ok, value} <- get_arg_value(value_arg, line, state.env) do
          put_byte(state, value) |> increment_pc() |> then(&{:ok, &1})
        end

      {:err, line} ->
        {:error, line, :err_directive}

      {{:skip, size_arg, fill_arg}, line} ->
        fill_result =
          case fill_arg do
            nil -> {:ok, 0}
            _ -> get_arg_value(fill_arg, line, state.env)
          end

        with {:ok, size_value} <- get_arg_value(size_arg, line, state.env),
             {:ok, fill_value} <- fill_result do
          case size_value do
            0 ->
              # Do nothing
              {:ok, state}

            _ ->
              new_state =
                for _ <- 1..size_value, reduce: state do
                  state ->
                    put_byte(state, fill_value) |> increment_pc()
                end

              {:ok, new_state}
          end
        end

      {{:rept, count_arg, loop_body}, line} ->
        with {:ok, count_value} <- get_arg_value(count_arg, line, state.env) do
          case count_value do
            0 ->
              # Do nothing
              {:ok, state}

            _ ->
              for _ <- 1..count_value, reduce: {:ok, state} do
                {:ok, state} ->
                  generate_all(loop_body, state)

                error ->
                  error
              end
          end
        end

      {{:irp, name, values, loop_body}, line} ->
        name = get_identifier_name(name, line, state.env)

        with {:ok, name} <- name do
          loop =
            for(value_arg <- values, reduce: {:ok, state}) do
              {:ok, state} ->
                with {:ok, value} <- get_arg_value(value_arg, line, state.env) do
                  generate_all(loop_body, %State{
                    state
                    | env: Map.put(state.env, "\\#{name}", value)
                  })
                end

              error ->
                error
            end

          with {:ok, new_state} <- loop do
            # Keep new values defined in the loop, but unset the arg
            {:ok, %State{new_state | env: Map.delete(new_state.env, "\\#{name}")}}
          end
        end

      {{:if, condition, if_body, else_body}, line} ->
        condition_true =
          case condition do
            {:defined?, {:identifier, name}} ->
              {:ok, Map.has_key?(state.env, name)}

            {:defined?, {:quoted_identifier, name}} ->
              with {:ok, value} <- get_quoted_identifier(name, line, state.env) do
                {:ok, Map.has_key?(state.env, value)}
              end

            {:not_defined?, {:identifier, name}} ->
              {:ok, not Map.has_key?(state.env, name)}

            {:not_defined?, {:quoted_identifier, name}} ->
              with {:ok, value} <- get_quoted_identifier(name, line, state.env) do
                {:ok, not Map.has_key?(state.env, value)}
              end

            arg ->
              with {:ok, arg_value} <- get_arg_value(arg, line, state.env) do
                {:ok, arg_value != 0}
              end
          end

        with {:ok, condition_true} <- condition_true do
          cond do
            # True case
            condition_true -> generate_all(if_body, state)
            # False case w/ else branch
            not is_nil(else_body) -> generate_all(else_body, state)
            # False case w/o else branch (do nothing)
            true -> {:ok, state}
          end
        end

      {{:macro, macro_name, macro_args, macro_body}, _} ->
        {:ok,
         %State{
           state
           | macros: Map.put(state.macros, macro_name, {macro_name, macro_args, macro_body})
         }}

      {:exit_macro, line_number} ->
        # A bit odd, but we need to bubble up until we hit a macro
        {{:exit_macro, line_number}, state}

      {{:call, opcode, args}, line_number} ->
        upcased_opcode = String.upcase(opcode)

        cond do
          Opcodes.is_opcode(upcased_opcode) ->
            generate_opcode_call(upcased_opcode, args, line_number, state)

          Map.has_key?(state.macros, opcode) ->
            generate_macro_call(Map.get(state.macros, opcode), args, line_number, state)

          true ->
            {:error, line_number, {:unknown_opcode, opcode}}
        end
    end
  end

  defp generate_opcode_call(opcode, args, line_number, state) do
    arg_values_result =
      args
      |> Enum.reduce_while({:ok, []}, fn arg, {:ok, args} ->
        case arg do
          nil ->
            {:halt, {:error, line_number, {:missing_opcode_argument, opcode}}}

          arg ->
            with {:ok, value} <- get_arg_value(arg, line_number, state.env) do
              {:cont, {:ok, args ++ [value]}}
            else
              error -> {:halt, error}
            end
        end
      end)

    with {:ok, arg_values} <- arg_values_result,
         {:ok, bytes} <- Opcodes.get_opcode(String.upcase(opcode), arg_values, line_number) do
      bytes
      |> Enum.reduce(state, &(&2 |> put_byte(&1) |> increment_pc()))
      |> then(&{:ok, &1})
    end
  end

  defp generate_macro_call(
         {macro_name, macro_args, macro_body},
         args,
         macro_line_number,
         state
       ) do
    if length(args) > length(macro_args) do
      {:error, macro_line_number,
       {:too_many_arguments, macro_name, length(macro_args), length(args)}}
    else
      define_macro_identifier = fn arg_name, name, env ->
        env
        |> Map.put("'#{arg_name}", name)
        # Even if this identifier isn't defined yet, it might be
        # defined during the course of the macro
        |> Map.put("\\#{arg_name}", fn line, env ->
          case Map.fetch(env, name) do
            :error ->
              {:error, line, {:undefined_symbol, name}}

            result ->
              result
          end
        end)
      end

      macro_env =
        Enum.zip(macro_args, args ++ List.duplicate(nil, length(macro_args) - length(args)))
        |> Enum.reduce_while({:ok, state.env}, fn {{arg_name, arg_default}, arg_value},
                                                  {:ok, env} ->
          case arg_value do
            {:identifier, name} ->
              # A lone identifier was passed, which is quotable and might not
              # be defined
              new_env = define_macro_identifier.(arg_name, name, env)
              {:cont, {:ok, new_env}}

            quoted_name = {:quoted_identifier, _} ->
              # Oh now we're getting meta
              with {:ok, name} <- get_identifier_name(quoted_name, macro_line_number, env) do
                new_env = define_macro_identifier.(arg_name, name, env)
                {:cont, {:ok, new_env}}
              else
                error -> {:halt, error}
              end

            _ when not is_nil(arg_value) ->
              # An expression was passed to this arg
              with {:ok, value} <- get_arg_value(arg_value, macro_line_number, env) do
                {:cont, {:ok, Map.put(env, "\\#{arg_name}", value)}}
              else
                error -> {:halt, error}
              end

            nil when not is_nil(arg_default) ->
              # Use this arg's default value
              with arg_default_value <- arg_default,
                   {:ok, value} <- get_arg_value(arg_default_value, macro_line_number, env) do
                {:cont, {:ok, Map.put(env, "\\#{arg_name}", value)}}
              else
                error -> {:halt, error}
              end

            _ ->
              # Nothing was passed and arg has no default
              {:halt,
               {:error, macro_line_number, {:missing_required_argument, macro_name, arg_name}}}
          end
        end)

      get_state = fn result ->
        case result do
          {:ok, state} -> {:ok, state}
          {{:exit_macro, _}, state} -> {:ok, state}
          error -> error
        end
      end

      with {:ok, macro_env} <- macro_env,
           generate_result <-
             generate_all(macro_body, %State{state | env: macro_env}),
           {:ok, new_state} <- get_state.(generate_result) do
        # Keep new values defined in the macro, but unset the args
        # If an arg was shadowed, restore its previous value
        unshadow = fn env, arg ->
          case Map.fetch(state.env, arg) do
            {:ok, value} -> Map.put(env, arg, value)
            :error -> Map.delete(env, arg)
          end
        end

        new_env =
          macro_args
          |> Enum.map(&elem(&1, 0))
          |> Enum.reduce(new_state.env, &(&2 |> unshadow.("\\#{&1}") |> unshadow.("'#{&1}")))

        {:ok, %State{new_state | env: new_env}}
      else
        {:error, line_number, error} when line_number != macro_line_number ->
          {:error, [line: line_number, macro_line: macro_line_number], error}

        error ->
          error
      end
    end
  end

  defp get_label_name(label, line, env) do
    label
    |> Enum.reduce_while({:ok, ""}, fn {label_part, part_name}, {:ok, label_name} ->
      case label_part do
        :constant ->
          {:cont, {:ok, label_name <> part_name}}

        :variable ->
          case Map.fetch(env, part_name) do
            {:ok, value} when is_integer(value) ->
              {:cont, {:ok, label_name <> Integer.to_string(value)}}

            {:ok, value} when is_binary(value) ->
              {:cont, {:ok, label_name <> value}}

            :error ->
              {:halt, {:error, line, {:undefined_symbol, part_name}}}
          end
      end
    end)
  end

  defp get_quoted_identifier(name, line, env) do
    case Map.fetch(env, "'#{name}") do
      :error -> {:error, line, {:undefined_symbol, "'#{name}"}}
      ok -> ok
    end
  end

  defp get_identifier_name(name, line, env) do
    case name do
      {:identifier, name} ->
        {:ok, name}

      {:quoted_identifier, name} ->
        get_quoted_identifier(name, line, env)
    end
  end

  defp get_arg_value(arg, line, env) do
    case arg do
      {type, _} when type in [:identifier, :quoted_identifier] ->
        with {:ok, name} <- get_identifier_name(arg, line, env) do
          case Map.fetch(env, name) do
            {:ok, func} when is_function(func) -> func.(line, env)
            {:ok, value} -> {:ok, value}
            :error -> {:error, line, {:undefined_symbol, name}}
          end
        end

      {:expression, expr} ->
        Expression.evaluate(expr, line, env)

      {:label_expression, label} ->
        with {:ok, label_name} <- get_label_name(label, line, env) do
          with {:ok, value} <- Map.fetch(env, label_name) do
            {:ok, value}
          else
            :error -> {:error, line, {:undefined_symbol, label_name}}
          end
        end
    end
  end

  # Adapted from https://github.com/mamedev/mame/blob/2d0088772029a2b788b1eeac64984fb375662410/src/devices/cpu/sm510/sm510base.cpp#L273-L280
  defp increment_pc(state) do
    page_mask = 63
    msb = bxor(page_mask >>> 1, page_mask)
    feed = if (bxor(state.pc >>> 1, state.pc) &&& 1) > 0, do: 0, else: msb
    new_pc = feed ||| (state.pc >>> 1 &&& page_mask >>> 1) ||| (state.pc &&& ~~~page_mask)

    %State{state | pc: new_pc}
  end

  defp put_byte(state, byte) do
    %State{state | data: Map.put(state.data, state.pc, <<byte::8>>)}
  end
end
