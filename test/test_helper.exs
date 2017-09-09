ExUnit.start()
ExUnit.configure(exclude: [:functional])
Ecto.Adapters.SQL.Sandbox.mode(PuntingServer.Repo, :manual)

