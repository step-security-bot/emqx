defmodule EMQXConf.MixProject do
  use Mix.Project
  Code.require_file("../../lib/emqx/mix/common.ex")

  @app :emqx_conf

  def project() do
    EMQX.Mix.Common.project(
      @app,
      deps: deps()
    )
  end

  def application() do
    EMQX.Mix.Common.application(@app)
  end

  defp deps() do
    [
      {:emqx, in_umbrella: true}
    ]
  end
end
