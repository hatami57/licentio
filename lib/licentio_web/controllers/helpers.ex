defmodule LicentioWeb.Controllers.Helpers do
  @moduledoc """
  Shared response helpers for all controllers.
  """

  import Phoenix.Controller, only: [json: 2]
  import Plug.Conn, only: [put_status: 2]

  def respond(conn, {:ok, data}, serializer) do
    json(conn, serializer.(data))
  end

  def respond(conn, {:error, reason}, _serializer) do
    {status, message} = error_info(reason)

    conn
    |> put_status(status)
    |> json(%{error: message})
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp error_info(:not_found), do: {:not_found, "Not found"}

  defp error_info(:tenant_mismatch),
    do: {:unprocessable_entity, "Feature belongs to a different tenant"}

  defp error_info(:insufficient_quota), do: {:unprocessable_entity, "Insufficient quota"}
  defp error_info(:not_reclaimable), do: {:unprocessable_entity, "Feature is not reclaimable"}

  defp error_info(:non_metric_feature),
    do: {:unprocessable_entity, "Feature is not a metric type"}

  defp error_info(:no_active_license), do: {:not_found, "No active license found"}
  defp error_info(:feature_not_found), do: {:not_found, "Feature not found"}
  defp error_info(_), do: {:internal_server_error, "Something went wrong"}
end
