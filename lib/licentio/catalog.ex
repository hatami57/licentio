defmodule Licentio.Catalog do
  @moduledoc """
  Context for managing features and plans within a tenant.
  """

  import Ecto.Query

  alias Licentio.Repo
  alias Licentio.Schema.{Feature, Plan, PlanFeature, PlanPrice}

  # ---------------------
  # Features
  # ---------------------

  def list_features(tenant_id) do
    Feature
    |> where([f], f.tenant_id == ^tenant_id and f.is_active == true)
    |> Repo.all()
  end

  def get_feature(id), do: Repo.get(Feature, id)

  def get_feature_by_code(tenant_id, code) do
    Repo.get_by(Feature, tenant_id: tenant_id, code: code)
  end

  def create_feature(attrs) do
    %Feature{}
    |> Feature.changeset(attrs)
    |> Repo.insert()
  end

  def update_feature(%Feature{} = feature, attrs) do
    feature
    |> Feature.changeset(attrs)
    |> Repo.update()
  end

  # ----------------------
  # Plans
  # ----------------------

  @doc """
  List all active plans for a tenant, with their features and prices preloaded.

  Preloading means Ecto will run additional queries to fetch associated records
  and nest them inside the struct for you - no manual joins needed.
  """
  def list_plans(tenant_id) do
    Plan
    |> where([p], p.tenant_id == ^tenant_id and p.is_active == true)
    |> preload([:plan_prices, plan_features: :feature])
    |> Repo.all()
  end

  def get_plan(id), do: Repo.get(Plan, id)

  def get_plan_by_code(tenant_id, code) do
    Repo.get_by(Plan, tenant_id: tenant_id, code: code)
  end

  def create_plan(attrs) do
    %Plan{}
    |> Plan.changeset(attrs)
    |> Repo.insert()
  end

  def update_plan(%Plan{} = plan, attrs) do
    plan
    |> Plan.changeset(attrs)
    |> Repo.update()
  end

  # ------------------------
  # Plan Features
  # ------------------------

  @doc """
  Adds a feature to a plan with a given value.

  For boolean features: value should be nil (presence = access granted).
  For metric features:  value is the limit (nil = unlimited).

  We validate here that the feature belongs to the same tenant as the plan.
  """
  def add_feature_to_plan(plan, feature, value \\ nil) do
    with :ok <- validate_same_tenant(plan, feature) do
      %PlanFeature{}
      |> PlanFeature.changeset(%{
        plan_id: plan.id,
        feature_id: feature.id,
        value: value
      })
      |> Repo.insert()
    end
  end

  def remove_feature_from_plan(%PlanFeature{} = plan_feature) do
    Repo.delete(plan_feature)
  end

  # ------------------
  # Plan Prices
  # ------------------

  def add_price_to_plan(plan, attrs) do
    %PlanPrice{}
    |> PlanPrice.changeset(Map.put(attrs, :plan_id, plan.id))
    |> Repo.insert()
  end

  # ------------------
  # Private helpers
  # ------------------

  defp validate_same_tenant(plan, feature) do
    if plan.tenant_id == feature.tenant_id do
      :ok
    else
      {:error, :tenant_mismatch}
    end
  end
end
