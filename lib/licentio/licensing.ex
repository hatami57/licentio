defmodule Licentio.Licensing do
  @moduledoc """
  Context for user registration, license management, and feature access/usage tracking.
  """

  import Ecto.Query

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
end
