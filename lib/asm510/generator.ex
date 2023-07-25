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
      {{:label, label_name}, _} ->
        {:ok, %State{state | env: Map.put_new(state.env, label_name, state.pc)}}

      {{:set, name, {:expression, value_expr}}, line} ->
        with {:ok, value} <- Expression.evaluate(value_expr, line, state.env) do
          {:ok, %State{state | env: Map.put(state.env, name, value)}}
        end

      {{:org, {:expression, expr}}, line} ->
        with {:ok, value} <- Expression.evaluate(expr, line, state.env) do
          {:ok, %State{state | pc: value}}
        end

      {{:word, {:expression, expr}}, line} ->
        with {:ok, value} <- Expression.evaluate(expr, line, state.env) do
          put_byte(state, value) |> increment_pc() |> then(&{:ok, &1})
        end

      {:err, line} ->
        {:error, line, :err_directive}

      {{:skip, {:expression, size_expr}, fill}, line} ->
        fill_result =
          case fill do
            {:expression, fill_expr} -> Expression.evaluate(fill_expr, line, state.env)
            nil -> {:ok, 0}
          end

        with {:ok, size_value} <- Expression.evaluate(size_expr, line, state.env),
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

      {{:rept, {:expression, count_expr}, loop_body}, line} ->
        with {:ok, count_value} <- Expression.evaluate(count_expr, line, state.env) do
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
        loop =
          for({:expression, value_expression} <- values, reduce: {:ok, state}) do
            {:ok, state} ->
              with {:ok, value} <- Expression.evaluate(value_expression, line, state.env) do
                generate_all(loop_body, %State{
                  state
                  | env: Map.put(state.env, "\\#{name}", value)
                })
              end

            error ->
              error
          end

        with {:ok, new_state} <- loop do
          # Restore env to its state prior to the loop
          {:ok, %State{new_state | env: state.env}}
        end

      {{:if, condition, if_body, else_body}, line} ->
        condition_true =
          case condition do
            {:expression, expression} ->
              with {:ok, expression_value} <- Expression.evaluate(expression, line, state.env) do
                {:ok, expression_value != 0}
              end

            {:defined?, name} ->
              {:ok, Map.has_key?(state.env, name)}

            {:not_defined?, name} ->
              {:ok, not Map.has_key?(state.env, name)}
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
          {:expression, expr} ->
            with {:ok, value} <- Expression.evaluate(expr, line_number, state.env) do
              {:cont, {:ok, args ++ [value]}}
            else
              error -> {:halt, error}
            end

          nil ->
            {:halt, {:error, line_number, {:missing_opcode_argument, opcode}}}
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
      macro_env =
        Enum.zip(macro_args, args ++ List.duplicate(nil, length(macro_args) - length(args)))
        |> Enum.reduce_while({:ok, %{}}, fn {{arg_name, arg_default}, arg_value}, {:ok, env} ->
          case arg_value do
            {:expression, expr} ->
              # An expression was passed to this arg
              with {:ok, value} <- Expression.evaluate(expr, macro_line_number, env) do
                {:cont, {:ok, Map.put(env, "\\#{arg_name}", value)}}
              else
                error -> {:halt, error}
              end

            nil when not is_nil(arg_default) ->
              # Use this arg's default value
              with {:expression, expr} <- arg_default,
                   {:ok, value} <- Expression.evaluate(expr, macro_line_number, env) do
                {:cont, {:ok, Map.put(env, "\\#{arg_name}", value)}}
              else
                error -> {:halt, error}
              end

            _ ->
              # No expression was passed and arg has no default
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
        # Restore env to its state prior to the macro
        {:ok, %State{new_state | env: state.env}}
      else
        {:error, line_number, error} when line_number != macro_line_number ->
          {:error, [line: line_number, macro_line: macro_line_number], error}

        error ->
          error
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
