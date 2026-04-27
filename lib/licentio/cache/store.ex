defmodule Licentio.Cache.Store do
  @moduledoc """
  Thin wrapper around ETS tables for fast in-memory lookups.

  Two tables:
    :lic_licenses -> {user_id, license_data}
    :lic_features -> {{user_id, feature_code}, feature_data}

  Both tables are :public so any process can read without
  going through the GenServer - concurrent reads, serialized writes.
  """

  @licenses_table :lic_licenses
  @features_table :lic_features
  @last_seen_table :lic_last_seen

  # Default TTL - evict users not seen for 30 minutes
  # Defined here so it can be read by TenantServer
  def default_ttl_seconds, do: 30 * 60

  # -----------------------------------------
  # Setup - called once when the app starts
  # -----------------------------------------

  def init_tables do
    opts = [:set, :public, :named_table, read_concurrency: true]

    for table <- [@licenses_table, @features_table, @last_seen_table] do
      if :ets.whereis(table) == :undefined do
        :ets.new(table, opts)
      end
    end

    :ok
  end

  # ----------------------------
  # TTL tracking
  # ----------------------------

  @doc "Record that a user was just active. Call on every cache hit."
  def touch(user_id) do
    :ets.insert(@last_seen_table, {user_id, System.monotonic_time(:second)})
  end

  @doc "Returns the last seen timestamp (monotonic seconds) for a user, or nil."
  def last_seen(user_id) do
    case :ets.lookup(@last_seen_table, user_id) do
      [{^user_id, ts}] -> ts
      [] -> nil
    end
  end

  @doc "Returns all {user_id, last_seen_ts} pairs in the TTL table."
  def all_last_seen do
    :ets.tab2list(@last_seen_table)
  end

  @doc "Remove a user's TTL entry."
  def delete_last_seen(user_id) do
    :ets.delete(@last_seen_table, user_id)
  end

  # ----------------------------
  # License operations
  # ----------------------------

  @doc "Stores a user's active license summary in ETS."
  def put_license(user_id, license_data) do
    :ets.insert(@licenses_table, {user_id, license_data})
    touch(user_id)
  end

  @doc "Fetch a user's active license summary. Returns nil if not cached."
  def get_license(user_id) do
    case :ets.lookup(@licenses_table, user_id) do
      [{^user_id, data}] ->
        touch(user_id)
        data

      [] ->
        nil
    end
  end

  @doc "Remove a user's license from cache (on expiry or revoke)."
  def delete_license(user_id) do
    :ets.delete(@licenses_table, user_id)
    delete_last_seen(user_id)
  end

  # ------------------------------
  # Feature operations
  # ------------------------------

  @doc "Store a single feature entry for a user."
  def put_feature(user_id, feature_code, feature_data) do
    :ets.insert(@features_table, {{user_id, feature_code}, feature_data})
  end

  @doc "Fetch a specific feature for a user. Returns nil if not cached."
  def get_feature(user_id, feature_code) do
    case :ets.lookup(@features_table, {user_id, feature_code}) do
      [{{^user_id, ^feature_code}, data}] ->
        touch(user_id)
        data

      [] ->
        nil
    end
  end

  @doc "Remove all feature entries for a user (on license change)."
  def delete_user_features(user_id) do
    :ets.match_delete(@features_table, {{user_id, :_}, :_})
    delete_last_seen(user_id)
  end

  @doc "Update just the used_value of a cached feature."
  def update_used_value(user_id, feature_code, new_used_value) do
    case get_feature(user_id, feature_code) do
      nil ->
        :not_found

      data ->
        put_feature(user_id, feature_code, %{data | used_value: new_used_value})
        :ok
    end
  end

  @doc "Returns all user_ids currently held in the license cache."
  def list_cached_user_ids do
    @licenses_table
    |> :ets.tab2list()
    |> Enum.map(fn {user_id, _data} -> user_id end)
  end
end
