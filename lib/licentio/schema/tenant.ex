defmodule Licentio.Schema.Tenant do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tenants" do
    field :name, :string
    field :code, :string
    field :is_active, :boolean, default: true
    field :metadata, :map, default: %{}

    has_many :features, Licentio.Schema.Feature
    has_many :plans, Licentio.Schema.Plan
    has_many :users, Licentio.Schema.User

    timestamps(type: :utc_datetime)
  end

  @required [:name, :code]
  @optional [:is_active, :metadata]

  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_length(:name, min: 2, max: 100)
    |> validate_format(:code, ~r/^[a-z0-9_-]+$/,
      message: "only lowercase letters, numbers, hyphens and underscores allowed"
    )
    |> validate_length(:code, min: 2, max: 60)
    |> unique_constraint(:code)
  end
end
