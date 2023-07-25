defmodule ASM510.CLI do
  alias ASM510.{Lexer, Parser, Generator}

  def main(argv \\ []) do
    start_time = :erlang.monotonic_time(:millisecond)

    with {:ok, in: input_path, out: output_path} <- parse_args(argv),
         {:ok, input_data} <- File.read(input_path),
         {:ok, tokens} <- Lexer.lex(input_data),
         {:ok, syntax} <- Parser.parse(tokens),
         {:ok, output_data} <- Generator.generate(syntax),
         :ok <- File.write(output_path, output_data) do
      millis = :erlang.monotonic_time(:millisecond) - start_time
      sha1 = :crypto.hash(:sha, output_data) |> Base.encode16()
      sha3 = :crypto.hash(:sha3_224, output_data) |> Base.encode64()
      IO.puts("Done in #{millis}ms\n    sha1: #{sha1}\nsha3-224: #{sha3}")
    else
      {:error, [line: line, macro_line: macro_line], error} ->
        IO.puts(
          :stderr,
          "Error on line #{line} in macro expanded at line #{macro_line}: #{error_message(error)}"
        )

      {:error, line, error} ->
        IO.puts(:stderr, "Error on line #{line}: #{error_message(error)}")
        exit(1)

      {:error, error} ->
        IO.puts(:stderr, "Error: #{error_message(error)}")
        exit(1)

      error ->
        IO.puts(:stderr, "Error: #{error_message(error)}")
        exit(1)
    end
  end

  defp parse_args(argv) do
    {switches, positional_args, invalid_options} =
      OptionParser.parse(argv, aliases: [o: :out], strict: [out: :string])

    with {:ok, out: output} <- parse_switches(switches),
         {:ok, in: input} <- parse_positional(positional_args),
         {:ok} <- parse_invalid(invalid_options) do
      {:ok, in: input, out: output}
    end
  end

  defp parse_switches([]), do: {:ok, out: "out.bin"}
  defp parse_switches(out: out), do: {:ok, out: out}

  defp parse_positional([]), do: {:error, :missing_input}
  defp parse_positional([input]), do: {:ok, in: input}
  defp parse_positional([_ | _]), do: {:error, :too_many_inputs}

  defp parse_invalid([]), do: {:ok}
  defp parse_invalid([invalid | _]), do: {:error, {:invalid_argument, invalid}}

  # Tokenizer errors
  defp error_message({:bad_identifier, name}), do: "Not a valid identifier: \"#{name}\""
  defp error_message({:bad_number, num}), do: "Not a valid number: \"#{num}\""

  # Parser errors
  defp error_message({:unexpected_token, token}),
    do: "Unexpected token: #{Lexer.token_to_string(token)}"

  defp error_message({:undefined_symbol, name}), do: "Undefined symbol: \"#{name}\""
  defp error_message({:invalid_directive, name}), do: "Invalid assembler directive: \"#{name}\""
  defp error_message({:reserved_name, name}), do: "Reserved name: \"#{name}\""
  defp error_message(:expected_name), do: "Expected name"

  defp error_message({:scope_not_closed, scope}),
    do: "No matching #{Parser.directive_to_close_scope(scope)} directive"

  # Generator errors
  defp error_message(:err_directive),
    do: "Reached .err directive"

  defp error_message({:unknown_opcode, opcode}), do: "Not an opcode or known macro: #{opcode}"

  defp error_message({:bad_opcode, opcode, arity}),
    do: "Wrong number of arguments given to opcode #{opcode}: #{arity}"

  defp error_message({:too_many_arguments, macro_name, expected_args, actual_args}),
    do:
      "Too many arguments passed to macro \"#{macro_name}\"; expected #{expected_args}, got #{actual_args}"

  defp error_message({:missing_required_argument, macro_name, arg_name}),
    do: "Macro \"#{macro_name}\" requires a value for argument \"#{arg_name}\""

  defp error_message({:missing_opcode_argument, opcode}),
    do: "Call to opcode \"#{opcode}\" is missing a required argument"

  defp error_message(:unexpected_exit_macro), do: "Found .exitm outside of a macro definition"

  # CLI errors
  defp error_message(:missing_input), do: "Missing input file"
  defp error_message(:too_many_inputs), do: "More than one input file was specified"
  defp error_message(:enoent), do: "File not found"

  # Other
  defp error_message(error), do: "Unknown error: #{inspect(error)}"
end
