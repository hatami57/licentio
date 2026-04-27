defmodule Licentio.Cache.TenantServer do
  @moduledoc """
  One GenServer process per active tenant.

  Responsibilities:
  - Load all active users + licenses for this tenant into ETS on startup
  - Handle consume/reclaim writes (serialized per tenant)
  - Reload a specific user when their license changes
  - Run a periodic check to expire stale licenses
  """

  use GenServer

  require Logger

  alias Ecto.Query.API
  alias Licentio.Cache.Store
  alias Licentio.Licensing
  alias Licentio.Repo
  alias Licentio.Schema.{License, LicenseFeature}

  import Ecto.Query

  @expiry_check_interval :timer.minutes(1)
  @ttl_check_interval :timer.minutes(5)

  # -----------------------------
  # Client API
  # -----------------------------

  def start_link(tenant_id) do
    GenServer.start_link(__MODULE__, tenant_id, name: via(tenant_id))
  end

  def load_user(tenant_id, user_id) do
    GenServer.cast(via(tenant_id), {:load_user, user_id})
  end

  def evict_user(tenant_id, user_id) do
    GenServer.cast(via(tenant_id), {:evict_user, user_id})
  end

  def consume(tenant_id, user_id, feature_code, units) do
    ensure_user_loaded(tenant_id, user_id)
    GenServer.call(via(tenant_id), {:consume, user_id, feature_code, units})
  end

  def reclaim(tenant_id, user_id, feature_code, units) do
    ensure_user_loaded(tenant_id, user_id)
    GenServer.call(via(tenant_id), {:reclaim, user_id, feature_code, units})
  end

  @doc """
  Checks if a user is already in the cache.
  If  not, triggers a load before the caller proceeds.
  This is the key to lazy loading - we only load on first touch.
  """
  def ensure_user_loaded(tenant_id, user_id) do
    case Store.get_license(user_id) do
      nil -> load_user(tenant_id, user_id)
      _ -> :ok
    end
  end

  # --------------------------
  # GenServer callbacks
  # --------------------------

  @impl true
  def init(tenant_id) do
    Logger.info("TenantServer started for tenant #{tenant_id}")

    schedule_expiry_check()
    schedule_ttl_check()

    {:ok, %{tenant_id: tenant_id}}
  end

  @impl true
  def handle_cast({:load_user, user_id}, state) do
    case Store.get_license(user_id) do
      nil ->
        load_user_into_cache(user_id)

      _ ->
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:evict_user, user_id}, state) do
    Store.delete_license(user_id)
    Store.delete_user_features(user_id)
    {:noreply, state}
  end

  @impl true
  def handle_call({:consume, user_id, feature_code, units}, _from, state) do
    result = do_consume(user_id, feature_code, units)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:reclaim, user_id, feature_code, units}, _from, state) do
    result = do_reclaim(user_id, feature_code, units)
    {:reply, result, state}
  end

  @impl true
  def handle_info(:check_expiry, %{tenant_id: tenant_id} = state) do
    expire_and_evict(tenant_id)
    schedule_expiry_check()
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_ttl, state) do
    evict_stale_users()
    sechedule_ttl_check()
    {:noreply, state}
  end

  # ---------------------------------------------
  # Private - loading (lazy, one user at a time)
  # ---------------------------------------------

  defp load_user_into_cache(user_id) do
    case Licensing.get_active_license(user_id) do
      nil ->
        Logger.debug("No active license found for user #{user_id}")
        :ok

      license ->
        cache_license(license)
        Logger.debug("Loaded user #{user_id} into cache")
    end
  end

  defp cache_license(license) do
    Store.put_license(license.user_id, %{
      id: license.id,
      plan_id: license.plan_id,
      expires_at: license.expires_at
    })

    Enum.each(license.license_features, fn lf ->
      Store.put_feature(license.user_id, lf.feature.code, %{
        feature_type: lf.feature.feature_type,
        is_reclaimable: lf.feature.is_reclaimable,
        is_unlimited: lf.feature.is_unlimited,
        unit_size: lf.feature.unit_size,
        granted_value: lf.granted_value,
        used_value: lf.used_value
      })
    end)
  end

  # -------------------------------------------------------------------
  # Private - expiry (only evicts cached users, not all tenant users)
  # -------------------------------------------------------------------

  defp expire_and_evict(tenant_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Only check licenses that are actually in our cache
    # We get cached user_ids from ETS directly
    cached_user_ids = Store.list_cached_user_ids()

    if Enum.empty?(cached_user_ids) do
      :ok
    else
      expired_user_ids =
        License
        |> where(
          [l],
          l.tenant_id == ^tenant_id and
            l.user_id in ^cached_user_ids and
            l.status == "active" and
            not is_nil(l.expires_at) and
            l.expires_at <= ^now
        )
        |> select([l], l.user_id)
        |> Repo.all()

      if not Enum.empty?(expired_user_ids) do
        License
        |> where([l], l.user_id in ^expired_user_ids and l.status == "active")
        |> Repo.update_all(set: [status: "expired"])

        Enum.each(expired_user_ids, fn user_id ->
          Store.delete_license(user_id)
          Store.delete_user_features(user_id)
        end)

        Logger.info("Expired #{length(expired_user_ids)} licenses for tenant #{tenant_id}")
      end
    end
  end

  defp evict_stale_users do
    now = System.monotonic_time(:second)
    ttl = Store.default_ttl_seconds()
    cutoff = now - ttl

    stale_user_ids =
      Store.all_last_seen()
      |> Enum.filter(fn {_user_id, last_seen_ts} -> last_seen_ts < cutoff end)
      |> Enum.map(fn {user_id, _} -> user_id end)

    Enum.each(stale_user_ids, fn user_id ->
      Store.delete_license(user_id)
      Store.delete_user_features(user_id)
      Logger.debug("Evicted stale user #{user_id} from cache (TTL exceeded)")
    end)

    if length(stale_user_ids) > 0 do
      Logger.info("TTL eviction: removed #{length(stale_user_ids)} inactive users from cache")
    end
  end

  # ----------------------------------------------
  # Private - consume & reclaim
  # ----------------------------------------------

  defp do_consume(user_id, feature_code, units) do
    with %{} = fd <- Store.get_feature(user_id, feature_code) || {:error, :feature_not_found},
         :ok <- check_is_metric(fd),
         :ok <- check_quota(fd, units) do
      new_used = fd.used_value + units

      case update_used_value_in_db(user_id, feature_code, new_used) do
        {:ok, _} ->
          Store.update_used_value(user_id, feature_code, new_used)
          {:ok, new_used}

        error ->
          error
      end
    end
  end

  defp do_reclaim(user_id, feature_code, units) do
    with %{} = fd <- Store.get_feature(user_id, feature_code) || {:error, :feature_not_found},
         :ok <- check_is_metric(fd),
         :ok <- check_reclaimable(fd) do
      new_used = max(fd.used_value - units, 0)

      case update_used_value_in_db(user_id, feature_code, new_used) do
        {:ok, _} ->
          Store.update_used_value(user_id, feature_code, new_used)
          {:ok, new_used}

        error ->
          error
      end
    end
  end

  defp update_used_value_in_db(user_id, feature_code, new_used) do
    result =
      LicenseFeature
      |> join(:inner, [lf], l in License, on: lf.license_id == l.id)
      |> join(:inner, [lf, _], f in Licentio.Schema.Feature, on: lf.feature_id == f.id)
      |> where(
        [lf, l, f],
        l.user_id == ^user_id and
          l.status == "active" and
          f.code == ^feature_code
      )
      |> Repo.update_all(set: [used_value: new_used])

    case result do
      {1, _} ->
        {:ok, new_used}

      {0, _} ->
        {:error, :not_found}
    end
  end

  defp check_is_metric(%{feature_type: "metric"}), do: :ok
  defp check_is_metric(_), do: {:error, :non_metric_feature}

  defp check_quota(%{is_unlimited: true}, _units), do: :ok

  defp check_quota(fd, units) do
    if fd.granted_value - fd.used_value >= units, do: :ok, else: {:error, :insufficient_quota}
  end

  defp check_reclaimable(%{is_reclaimable: true}), do: :ok
  defp check_reclaimable(_), do: {:error, :not_reclaimable}

  defp schedule_expiry_check do
    Process.send_after(self(), :check_expiry, @expiry_check_interval)
  end

  defp schedule_ttl_check do
    Process.send_after(self(), :check_ttl, @ttl_check_interval)
  end

  defp via(tenant_id) do
    {:via, Registry, {Licentio.TenantRegistry, tenant_id}}
  end
end
