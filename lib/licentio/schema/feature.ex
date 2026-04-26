defmodule Licentio.Schema.Feature do
  use Ecto.Schema
  import Ecto.Changeset

  @feature_types ~w(boolean metric)
  def feature_types, do: @feature_types

  schema "features" do
    belongs_to :tenant, Licentio.Schema.Tenant, type: :binary_id

    field :name, :string
    field :code, :string
    field :description, :string
    field :feature_type, :string

    field :is_reclaimable, :boolean, default: false
    field :is_extendable, :boolean, default: false
    field :is_unlimited, :boolean, default: false
    field :unit_size, :decimal
    field :unit_label, :string

    field :is_active, :boolean, default: true

    has_many :plan_features, Licentio.Schema.PlanFeature
    has_many :license_features, Licentio.Schema.LicenseFeature

    timestamps(type: :utc_datetime)
  end

  @required [:tenant_id, :name, :code, :feature_type]
  @optional [
    :description,
    :is_active,
    :is_reclaimable,
    :is_extendable,
    :is_unlimited,
    :unit_size,
    :unit_label
  ]

  def changeset(feature, attrs) do
    feature
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:feature_type, @feature_types)
    |> validate_format(:code, ~r/^[a-z0-9_-]+$/,
      message: "only lowercase letters, numbers and underscores allowed"
    )
    |> validate_length(:code, min: 2, max: 60)
    |> unique_constraint(:code, name: :features_tenant_id_code_index)
    |> validate_metric_config()
  end

  defp validate_metric_config(changeset) do
    case get_field(changeset, :feature_type) do
      "boolean" -> validate_no_metric_fields(changeset)
      "metric" -> validate_metric_fields(changeset)
      _ -> changeset
    end
  end

  defp validate_no_metric_fields(changeset) do
    metric_fields = [:is_reclaimable, :is_extendable, :is_unlimited, :unit_size, :unit_label]

    Enum.reduce(metric_fields, changeset, fn field, cs ->
      case get_field(cs, field) do
        nil -> cs
        false -> cs
        _ -> add_error(cs, field, "must be empty for boolean features")
      end
    end)
  end

  defp validate_metric_fields(changeset) do
    changeset
    |> validate_required([:unit_size, :unit_label],
      message: "is required for metric features"
    )
    |> validate_number(:unit_size,
      greater_than: 0,
      message: "must be greater than 0"
    )
    |> validate_length(:unit_label, min: 1, max: 20)
    |> validate_unlimited_exclusivity()
  end

  defp validate_unlimited_exclusivity(changeset) do
    if get_field(changeset, :is_unlimited) do
      changeset
      |> validate_false(:is_reclaimable, message: "cannot be true when feature is unlimited")
      |> validate_false(:is_extendable, message: "cannot be true when feature is unlimited")
    else
      changeset
    end
  end

  defp validate_false(changeset, field, opts) do
    if get_field(changeset, field) == true do
      add_error(changeset, field, opts[:message])
    else
      changeset
    end
  end
end
