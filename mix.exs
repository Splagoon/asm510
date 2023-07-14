defmodule Asm510.MixProject do
  use Mix.Project

  def project do
    [
      app: :asm510,
      version: "1.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: LcovEx, output: "cover"],
      escript: [main_module: ASM510.CLI]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:lcov_ex, "~> 0.3", only: [:dev, :test], runtime: false}
    ]
  end
end
