defmodule AwfulNntp.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:awful_nntp, :port, 1199)

    children = [
      # Dynamic supervisor for connection handlers
      {DynamicSupervisor, name: AwfulNntp.ConnectionSupervisor, strategy: :one_for_one},
      # TCP server
      %{
        id: AwfulNntp.NNTP.Server,
        start: {AwfulNntp.NNTP.Server, :start_link, [[port: port]]}
      }
    ]

    opts = [strategy: :one_for_one, name: AwfulNntp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
