defmodule Licentio.Schema.License do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(active expired revoked)
  def statuses, do: @statuses

  schema "licenses" do
    belongs_to :tenant, Licentio.Schema.Tenant, type: :binary_id
    belongs_to :user, Licentio.Schema.User
    belongs_to :plan, Licentio.Schema.Plan

    field :status, :string, default: "active"
    field :starts_at, :utc_datetime
    field :expires_at, :utc_datetime

    has_many :license_features, Licentio.Schema.LicenseFeature

    timestamps(type: :utc_datetime)
  end

  @required [:tenant_id, :user_id, :plan_id, :starts_at]
  @optional [:status, :expires_at]

  def changeset(license, attrs) do
    license
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:status, @statuses)
    |> validate_expiry()
  end

  def revoke_changeset(license) do
    license
    |> change(status: "revoked")
  end

  def expire_changeset(license) do
    license
    |> change(status: "expired")
  end

  defp validate_expiry(changeset) do
    starts_at = get_field(changeset, :starts_at)
    expires_at = get_field(changeset, :expires_at)

    if starts_at && expires_at && DateTime.compare(expires_at, starts_at) != :gt do
      add_error(changeset, :expires_at, "must be after starts_at")
    else
      changeset
    end
  end
end
