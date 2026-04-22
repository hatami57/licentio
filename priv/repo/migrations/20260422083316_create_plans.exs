defmodule Licentio.Repo.Migrations.CreatePlans do
  use Ecto.Migration

  def change do
    create table(:plans) do
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :code, :string, null: false
      add :name, :string, null: false
      add :description, :string
      add :is_default, :boolean, default: false, null: false
      add :is_active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:plans, [:tenant_id, :code])

    create unique_index(:plans, [:tenant_id, :is_default],
             where: "is_default = true",
             name: :one_default_plan_per_tenant
           )

    create table(:plan_prices) do
      add :plan_id, references(:plans, on_delete: :delete_all), null: false
      add :duration_unit, :string, null: false
      add :duration_value, :integer
      add :price, :decimal, precision: 10, scale: 2, null: false
      add :currency, :string, default: "USD", null: false
      add :is_active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:plan_prices, [:plan_id])
  end
end
