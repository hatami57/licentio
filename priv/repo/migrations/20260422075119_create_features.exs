defmodule Licentio.Repo.Migrations.CreateFeatures do
  use Ecto.Migration

  def change do
    create table(:features) do
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :code, :string, null: false
      add :name, :string, null: false
      add :description, :string
      add :feature_type, :string, null: false

      add :is_reclaimable, :boolean, default: false, null: false
      add :is_extendable, :boolean, default: false, null: false
      add :is_unlimited, :boolean, default: false, null: false
      add :unit_size, :decimal, precision: 20, scale: 6
      add :unit_label, :string

      add :is_active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:features, [:tenant_id, :code])
    create index(:features, [:tenant_id])
  end
end
