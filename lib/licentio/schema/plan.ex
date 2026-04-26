defmodule Licentio.Schema.Plan do
  use Ecto.Schema
  import Ecto.Changeset

  schema "plans" do
    belongs_to :tenant, Licentio.Schema.Tenant, type: :binary_id

    field :name, :string
    field :code, :string
    field :description, :string
    field :is_default, :boolean, default: true
    field :is_active, :boolean, default: true

    has_many :plan_prices, Licentio.Schema.PlanPrice
    has_many :plan_features, Licentio.Schema.PlanFeature
    has_many :licenses, Licentio.Schema.License

    timestamps(type: :utc_datetime)
  end

  @required [:tenant_id, :name, :code]
  @optional [:description, :is_default, :is_active]

  def changeset(plan, attrs) do
    plan
      |> cast(attrs, @required ++ @optional)
      |> validate_required(@required)
      |> validate_format(:code, ~r/^[a-z0-9_-]+$/,
      message: "only lowercase letters, numbers and underscores allowed")
      |> validate_length(:name, min: 2, max: 100)
      |> validate_length(:code, min: 2, max: 60)
      |> unique_constraint(:code, name: :plans_tenant_id_code_index)
      |> unique_constraint(:is_default, name: :one_default_plan_per_tenant,
    message: "a default plan already exists for this tenant")
  end
end
