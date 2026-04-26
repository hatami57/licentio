defmodule Licentio.Schema.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    belongs_to :tenant, Licentio.Schema.Tenant, type: :binary_id

    field :external_id, :binary_id
    field :is_active,   :boolean, default: true
    field :metadata,    :map,     default: %{}

    has_many :licenses, Licentio.Schema.License

    timestamps(type: :utc_datetime)
  end

  @required [:tenant_id, :external_id]
  @optional [:is_active, :metadata]

  def changeset(user, attrs) do
    user
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> unique_constraint(:external_id, name: :users_tenant_id_external_id_index,
        message: "user already registered for this tenant")
  end
end
