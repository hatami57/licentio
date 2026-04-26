defmodule Licentio.Licensing do
  @moduledoc """
  Context for user registration, license management, and feature access/usage tracking.
  """

  import Ecto.Query

  alias Phoenix.LiveView.Lifecycle
  alias Ecto.Multi
  alias Licentio.Repo
  alias Licentio.Schema.{User, License, LicenseFeature, Plan, PlanFeature}

  # ---------------------
  # User Registration
  # ---------------------

  @doc """
  Registers a new user for a tenant and automatically grants
  the tenant's default plan license if one exists.

  This entire operation is wrapped in a transaction - either the user
  is created AND gets their default license, or nothing happens.

  ## Example
      Licensing.register_user(tenant, "ext-uuid-from-your-app")
      #=> {:ok, %{user: %User{}, license: %License{}}}
      #=> {:ok, %{user: %User{}, license: nil}} # no default plan defined
  """
  def register_user(tenant, external_id) do
    Multi.new()
    |> Multi.insert(:user, user_changeset(tenant.id, external_id))
    |> Multi.run(:license, fn repo, %{user: user} ->
      grant_default_license(repo, tenant, user)
    end)
    |> Repo.transact()
  end

  # ---------------------
  # License Granting
  # ---------------------

  @doc """
  Grants a specific plan to a user for a given duration.

  `duration` is a map like:
   %{unit: "month", value: 1} -> 1 month from now
   %{unit: "forever"}         -> never expire

  Steps:
    1. Expire any current active license
    2. Create the new license
    3. Snapshot all plan features into license_features
  """
  def grant_license(tenant, user, plan, duration) do
    starts_at = DateTime.utc_now() |> DateTime.truncate(:second)
    expires_at = calculate_expiry(starts_at, duration)

    Multi.new()
    |> Multi.run(:expire_current, fn repo, _changes ->
      expire_active_license(repo, user.id)
    end)
    |> Multi.insert(
      :license,
      license_changeset(tenant.id, user.id, plan.id, starts_at, expires_at)
    )
    |> Multi.run(:features, fn repo, %{license: license} ->
      snapshot_plan_features(repo, license, plan)
    end)
    |> Repo.transaction()
  end

  # ------------------------------------
  # Active License & Feature Queries
  # ------------------------------------

  @doc """
  Returns the currently active license for a user, with features preloaded.
  Returns nil if no active license exists.
  """
  def get_active_license(user_id) do
    License
    |> where([l], l.user_id == ^user_id and l.status == "active")
    |> preload(license_features: :feature)
    |> Repo.one()
  end

  @doc """
  Checks whether a user has access to a specific feature.

  For boolean features -> true if the feature exists in their license
  For metric features  -> true if they have remaining value OR it's unlimited
  """
  def has_access?(user_id, feature_code) do
    with %License{} = license <- get_active_license(user_id),
         %LicenseFeature{} = lf <- find_license_feature(license, feature_code) do
      check_access(lf)
    else
      _ -> false
    end
  end

  @doc """
  Returns the current usage info for a metric feature.

      {:ok, %{granted: 100, used: 40, remaining: 60, unlimited: false}}
      {:error, :no_active_license}
      {:error, :feature_not_found}
  """
  def get_feature_usage(user_id, feature_code) do
    with %License{} = license <- get_active_license(user_id),
         %LicenseFeature{} = lf <- find_license_feature(license, feature_code) do
      {:ok, build_usage_map(lf)}
    else
      nil -> {:error, :no_active_license}
      _ -> {:error, :feature_not_found}
    end
  end

  # --------------------------
  # Usage tracking
  # --------------------------

  @doc """
  Consumes `raw_amount` units of a metric feature for a user.

  raw_amount is in the feature's base unit (e.g. bytes for storage).
  We convert to feature units using unit_size before deducting.

  Returns:
    {:ok, %LicenseFeature{}}      -> sucess
    {:error, :insufficient_quota} -> not enough remaining
    {:error, :non_metric_feature} -> tried to consume a boolean feature
    {:error, :no_active_license}
    {:error, :feature_not_found}
  """
  def consume(user_id, feature_code, raw_amount) do
    with %License{} = license <- get_active_license(user_id),
         %LicenseFeature{} = lf <- find_license_feature(license, feature_code),
         :ok <- validate_is_metric(lf),
         units <- convert_to_units(raw_amount, lf.feature.unit_size),
         :ok <- validate_quota(lf, units) do
      deduct_usage(lf, units)
    else
      nil -> {:error, :no_active_license}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Reclaims `raw_amount` units back to a user's metric feature.

  Only works if the feature has is_reclaimable = true.

  Returns:
    {:ok, %LicenseFeature{}}     -> success
    {:error, :not_reclaimable}   -> feature doesn't support reclaim
    {:error, :no_active_license}
    {:error, :feature_not_found}
  """
  def reclaim(user_id, feature_code, raw_amount) do
    with %License{} = license <- get_active_license(user_id),
         %LicenseFeature{} = lf <- find_license_feature(license, feature_code),
         :ok <- validate_is_metric(lf),
         :ok <- validate_reclaimable(lf),
         units <- convert_to_units(raw_amount, lf.feature.unit_size) do
      restore_usage(lf, units)
    else
      nil -> {:error, :no_active_license}
      {:error, reason} -> {:error, reason}
    end
  end

  # ----------------------------
  # License Lifecycle
  # ----------------------------

  @doc """
  Revokes a license immediately regardless of expiry date.
  """
  def revoke_license(%License{} = license) do
    license
    |> License.revoke_changeset()
    |> Repo.update()
  end

  @doc """
  Marks all active licenses that have passed their expiry date as expired.
  This should be called periodically.
  """
  def expire_stale_licenses do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      License
      |> where([l], l.status == "active" and l.expires_at <= ^now)
      |> Repo.update_all(set: [status: "expired"])

    {:ok, count}
  end

  # ------------------------
  # Private - changesets
  # ------------------------

  defp user_changeset(tenant_id, external_id) do
    User.changeset(%User{}, %{
      tenant_id: tenant_id,
      external_id: external_id
    })
  end

  defp license_changeset(tenant_id, user_id, plan_id, starts_at, expires_at) do
    License.changeset(%License{}, %{
      tenant_id: tenant_id,
      user_id: user_id,
      plan_id: plan_id,
      starts_at: starts_at,
      expires_at: expires_at,
      status: "active"
    })
  end

  # -----------------------------------
  # Private - license granting helpers
  # -----------------------------------

  defp grant_default_license(repo, tenant, user) do
    case repo.get_by(Plan, tenant_id: tenant.id, is_default: true) do
      nil -> {:ok, nil}
      plan -> do_grant_license(repo, tenant, user, plan)
    end
  end

  defp do_grant_license(repo, tenant, user, plan) do
    starts_at = DateTime.utc_now() |> DateTime.truncate(:second)

    license_attrs = %{
      tenant_id: tenant.id,
      user_id: user.id,
      plan_id: plan.id,
      starts_at: starts_at,
      expires_at: nil,
      status: "active"
    }

    with {:ok, license} <- repo.insert(License.changeset(%License{}, license_attrs)),
         {:ok, _} <- snapshot_plan_features(repo, license, plan) do
      {:ok, license}
    end
  end

  defp expire_active_license(repo, user_id) do
    {_count, _} =
      License
      |> where([l], l.user_id == ^user_id and l.status == "active")
      |> repo.update_all(set: [status: "expired"])

    {:ok, :done}
  end

  # -----------------------------
  # Private - feature snapshot
  # -----------------------------

  @doc """
  Copies all active plan features into license_features for a granted license.

  This is the snapshot - from this point on, the license_features record
  is independent of the plan. If the plan changes later, this license
  is unaffected.
  """
  def snapshot_plan_features(repo, license, plan) do
    plan_features =
      PlanFeature
      |> where([pf], pf.plan_id == ^plan.id and pf.is_active == true)
      |> repo.all()

    result =
      Enum.reduce_while(plan_features, {:ok, []}, fn pf, {:ok, acc} ->
        attrs = %{
          license_id: license.id,
          feature_id: pf.feature_id,
          granted_value: pf.value,
          used_value: 0
        }

        case repo.insert(LicenseFeature.changeset(%LicenseFeature{}, attrs)) do
          {:ok, lf} -> {:cont, {:ok, [lf | acc]}}
          {:error, cs} -> {:halt, {:error, cs}}
        end
      end)

    result
  end

  # ---------------------------------
  # Private - access & usage helpers
  # ---------------------------------

  defp find_license_feature(license, feature_code) do
    Enum.find(license.license_features, fn lf ->
      lf.feature.code == feature_code
    end)
  end

  defp check_access(%LicenseFeature{} = lf) do
    case lf.feature.feature_type do
      "boolean" ->
        true

      "metric" ->
        lf.feature.is_unlimited or remaining(lf) > 0
    end
  end

  defp build_usage_map(%LicenseFeature{} = lf) do
    %{
      granted: lf.granted_value,
      used: lf.used_value,
      remaining: remaining(lf),
      unlimited: lf.feature.is_unlimited
    }
  end

  defp remaining(%LicenseFeature{} = lf) do
    if lf.feature.is_unlimited do
      :infinity
    else
      lf.granted_value - lf.used_value
    end
  end

  defp validate_is_metric(%LicenseFeature{} = lf) do
    if lf.feature.feature_type == "metric" do
      :ok
    else
      {:error, :non_metric_feature}
    end
  end

  defp validate_reclaimable(%LicenseFeature{} = lf) do
    if lf.feature.is_reclaimable do
      :ok
    else
      {:error, :not_reclaimable}
    end
  end

  defp validate_quota(%LicenseFeature{} = lf, units) do
    cond do
      lf.feature.is_unlimited -> :ok
      remaining(lf) >= units -> :ok
      true -> {:error, :insufficient_quota}
    end
  end

  # ----------------------------
  # Private - unit conversion
  # ----------------------------

  @doc """
  Converts a raw amount to feature units, rounding up.

  Example: 5200 bytes with unit_size=1024 -> ceil(5200/1024) = 6 KB units
  """
  defp convert_to_units(raw_amount, unit_size) do
    (raw_amount / Decimal.to_float(unit_size))
    |> :math.ceil()
    |> trunc()
  end

  # ------------------------------
  # Private - DB writes for usage
  # ------------------------------

  defp deduct_usage(%LicenseFeature{} = lf, units) do
    lf
    |> LicenseFeature.changeset(%{used_value: lf.used_value + units})
    |> Repo.update()
  end

  defp restore_usage(%LicenseFeature{} = lf, units) do
    new_used = max(lf.used_value - units, 0)

    lf
    |> LicenseFeature.changeset(%{used_value: new_used})
    |> Repo.update()
  end

  # -----------------------------
  # Private - expiry calculation
  # -----------------------------

  defp calculate_expiry(_starts_at, %{unit: "forever"}), do: nil

  defp calculate_expiry(starts_at, %{unit: "day", value: v}), do: shift(starts_at, days: v)
  defp calculate_expiry(starts_at, %{unit: "month", value: v}), do: shift(starts_at, months: v)
  defp calculate_expiry(starts_at, %{unit: "year", value: v}), do: shift(starts_at, years: v)

  defp shift(datetime, unit_opts) do
    datetime
    |> DateTime.to_naive()
    |> NaiveDateTime.add(duration_in_seconds(unit_opts))
    |> DateTime.from_naive!("Etc/UTC")
  end

  defp duration_in_seconds(days: d), do: d * 86_400
  defp duration_in_seconds(months: m), do: m * 30 * 86_400
  defp duration_in_seconds(years: y), do: y * 365 * 86_400
end
