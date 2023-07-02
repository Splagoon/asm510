defmodule ASM510.Generator.State do
  defstruct pc: 0, env: %{}, data: %{}
end

defmodule ASM510.Generator do
  import Bitwise

  alias ASM510.{Generator.State, Opcodes}

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

      {{:call, ".set", [{:name, name}, value_arg]}, line_number} ->
        with {:ok, value} <- get_number_arg(value_arg, state, line_number) do
          {:ok, %State{state | env: Map.put_new(state.env, name, value)}}
        end

      {{:call, ".org", [arg]}, line_number} ->
        with {:ok, value} <- get_number_arg(arg, state, line_number) do
          {:ok, %State{state | pc: value}}
        end

      {{:call, ".word", [arg]}, line_number} ->
        with {:ok, value} <- get_number_arg(arg, state, line_number) do
          put_byte(state, value) |> increment_pc() |> then(&{:ok, &1})
        end

      {{:call, opcode, args}, line_number} ->
        arg_values_result =
          args
          |> Enum.reduce_while({:ok, []}, fn arg, {:ok, args} ->
            with {:ok, value} <- get_number_arg(arg, state, line_number) do
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

  defp get_number_arg({:number, value}, _, _), do: {:ok, value}

  defp get_number_arg({:name, name}, state, line_number) do
    with {:ok, value} <- Map.fetch(state.env, name) do
      {:ok, value}
    else
      :error -> {:error, line_number, {:undefined_name, name}}
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
