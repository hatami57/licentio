defmodule LicentioWeb.FeatureController do
  use LicentioWeb, :controller

  alias Licentio.Catalog
  alias LicentioWeb.Controllers.Helpers

  def index(conn, _params) do
    tenant = conn.assigns.tenant
    features = Catalog.list_features(tenant.id)
    json(conn, Enum.map(features, &serialize/1))
  end

  def create(conn, params) do
    tenant = conn.assigns.tenant
    attrs = Map.put(params, "tenant_id", tenant.id)
    Helpers.respond(conn, Catalog.create_feature(attrs), &serialize/1)
  end

  defp serialize(f) do
    base = %{
      id: f.id,
      name: f.name,
      code: f.code,
      description: f.description,
      feature_type: f.feature_type,
      is_active: f.is_active
    }

    if f.feature_type == "metric" do
      Map.merge(base, %{
        is_reclaimable: f.is_reclaimable,
        is_extendable: f.is_extendable,
        is_unlimited: f.is_unlimited,
        unit_size: f.unit_size,
        unit_label: f.unit_label
      })
    else
      base
    end
  end
end
