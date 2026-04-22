defmodule Licentio.Repo do
  use Ecto.Repo,
    otp_app: :licentio,
    adapter: Ecto.Adapters.Postgres
end
