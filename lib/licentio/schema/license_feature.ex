defmodule Licentio.Schema.LicenseFeature do
  use Ecto.Schema
  import Ecto.Changeset

  schema "license_features" do
    belongs_to :license, Licentio.Schema.License
    belongs_to :feature, Licentio.Schema.Feature

    field :granted_value, :integer
    field :used_value, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @required [:license_id, :feature_id]
  @optional [:granted_value, :used_value]

  def changeset(license_feature, attrs) do
    license_feature
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> unique_constraint(:feature_id, name: :license_features_license_id_feature_id_index)
    |> validate_number(:granted_value, greater_than_or_equal_to: 0)
    |> validate_number(:used_value, greater_than_or_equal_to: 0)
    |> validate_usage_within_grant()
  end

  defp validate_usage_within_grant(changeset) do
    granted = get_field(changeset, :granted_value)
    used = get_field(changeset, :used_value)

    if granted && used && used > granted do
      add_error(changeset, :used_value, "cannot exceed granted_value")
    else
      changeset
    end
  end
end
