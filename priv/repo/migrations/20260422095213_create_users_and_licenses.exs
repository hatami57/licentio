defmodule Licentio.Repo.Migrations.CreateUsersAndLicenses do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :external_id, :uuid, null: false
      add :is_active, :boolean, default: true, null: false
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:tenant_id, :external_id])
    create index(:users, [:tenant_id])

    create table(:licenses) do
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :plan_id, references(:plans, on_delete: :restrict), null: false
      add :status, :string, null: false, default: "active"
      add :starts_at, :utc_datetime, null: false
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:licenses, [:tenant_id])
    create index(:licenses, [:user_id])
    create index(:licenses, [:user_id, :status])

    create table(:license_features) do
      add :license_id, references(:licenses, on_delete: :delete_all), null: false
      add :feature_id, references(:features, on_delete: :restrict), null: false
      add :granted_value, :bigint
      add :used_value, :bigint, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:license_features, [:license_id, :feature_id])
    create index(:license_features, [:feature_id])
  end
end
