defmodule Emmer.Repo do
  use Ecto.Repo,
    otp_app: :emmer,
    adapter: Ecto.Adapters.SQLite3
end
