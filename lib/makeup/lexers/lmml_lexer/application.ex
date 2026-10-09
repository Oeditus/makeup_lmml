defmodule Makeup.Lexers.LmmlLexer.Application do
  @moduledoc false
  use Application

  alias Makeup.{Lexers.LmmlLexer, Registry}

  def start(_type, _args) do
    Registry.register_lexer(LmmlLexer,
      options: [],
      names: ["lmml", "markdown", "md"],
      extensions: ["lmml", "md", "markdown"]
    )

    Supervisor.start_link([], strategy: :one_for_one)
  end
end
