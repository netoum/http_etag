defmodule HttpEtag.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/netoum/http_etag"
  @rfc_url "https://www.rfc-editor.org/rfc/rfc9110.html"

  def project do
    [
      app: :http_etag,
      name: "HttpEtag",
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      dialyzer: dialyzer(),
      test_coverage: [summary: [threshold: 100]]
    ]
  end

  def application do
    [
      extra_applications: [:crypto]
    ]
  end

  defp deps do
    [
      {:plug, "~> 1.15", optional: true},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:plug],
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
    ]
  end

  defp description do
    "RFC 9110 entity tags and If-Match / If-None-Match for Elixir."
  end

  defp package do
    [
      licenses: ["MIT"],
      files:
        ~w(lib mix.exs README.md CHANGELOG.md LICENSE .formatter.exs CONTRIBUTING.md CODE_OF_CONDUCT.md),
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "RFC 9110" => @rfc_url,
        "JSON Merge Patch" => "https://hex.pm/packages/json_merge_patch"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CHANGELOG.md": [title: "Changelog"],
        "CONTRIBUTING.md": [title: "Contributing"],
        "CODE_OF_CONDUCT.md": [title: "Code of Conduct"]
      ],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"],
      groups_for_modules: [
        Plug: [HttpEtag.Conn]
      ]
    ]
  end
end
