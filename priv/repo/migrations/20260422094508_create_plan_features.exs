defmodule Licentio.Repo.Migrations.CreatePlanFeatures do
  use Ecto.Migration

  def change do
    create table(:plan_features) do
      add :plan_id, references(:plans, on_delete: :delete_all), null: false
      add :feature_id, references(:features, on_delete: :delete_all), null: false
      add :value, :bigint
      add :is_active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:plan_features, [:plan_id, :feature_id])
    create index(:plan_features, [:feature_id])
  end
end
