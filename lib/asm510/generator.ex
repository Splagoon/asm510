defmodule ASM510.Generator.State do
  defstruct pc: 0, env: %{}, data: %{}
end

defmodule ASM510.Generator do
  import Bitwise

  alias ASM510.{Generator.State, Opcodes, Expression}

  def generate(syntax) do
    with {:ok, state} <- generate_all(syntax, %State{}) do
      state.data
      |> assemble_rom(4096)
      |> then(&{:ok, &1})
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

      # First arg to .set is expected to be an undefined symbol
      {{:call, ".set", [{:expression, [identifier: name]}, {:expression, value_expr}]}, _} ->
        with {:ok, value} <- Expression.evaluate(value_expr, state.env) do
          {:ok, %State{state | env: Map.put_new(state.env, name, value)}}
        end

      {{:call, ".org", [{:expression, expr}]}, _} ->
        with {:ok, value} <- Expression.evaluate(expr, state.env) do
          {:ok, %State{state | pc: value}}
        end

      {{:call, ".word", [{:expression, expr}]}, _} ->
        with {:ok, value} <- Expression.evaluate(expr, state.env) do
          put_byte(state, value) |> increment_pc() |> then(&{:ok, &1})
        end

      {{:call, opcode, args}, line_number} ->
        arg_values_result =
          args
          |> Enum.reduce_while({:ok, []}, fn {:expression, expr}, {:ok, args} ->
            with {:ok, value} <- Expression.evaluate(expr, state.env) do
              {:cont, {:ok, args ++ [value]}}
            else
              error -> {:halt, error}
            end
          end)

        with {:ok, arg_values} <- arg_values_result,
             {:ok, bytes} <- Opcodes.get_opcode(String.upcase(opcode), arg_values, line_number) do
          bytes
          |> Enum.reduce(state, &(&2 |> put_byte(&1) |> increment_pc()))
          |> then(&{:ok, &1})
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
