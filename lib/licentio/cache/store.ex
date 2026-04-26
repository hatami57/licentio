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

  # -----------------------------------------
  # Setup - called once when the app starts
  # -----------------------------------------

  def init_tables do
    opts = [:set, :public, :named_table, read_concurrency: true]

    if :ets.whereis(@licenses_table) == :undefined do
      :ets.new(@licenses_table, opts)
    end

    if :ets.whereis(@features_table) == :undefined do
      :ets.new(@features_table, opts)
    end

    :ok
  end

  # ----------------------------
  # License operations
  # ----------------------------

  @doc "Stores a user's active license summary in ETS."
  def put_license(user_id, license_data) do
    :ets.insert(@licenses_table, {user_id, license_data})
  end

  @doc "Fetch a user's active license summary. Returns nil if not cached."
  def get_license(user_id) do
    case :ets.lookup(@licenses_table, user_id) do
      [{^user_id, data}] -> data
      [] -> nil
    end
  end

  @doc "Remove a user's license from cache (on expiry or revoke)."
  def delete_license(user_id) do
    :ets.delete(@licenses_table, user_id)
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
        data

      [] ->
        nil
    end
  end

  @doc "Remove all feature entries for a user (on license change)."
  def delete_user_features(user_id) do
    :ets.match_delete(@features_table, {{user_id, :_}, :_})
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
end
