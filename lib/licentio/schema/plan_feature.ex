defmodule Licentio.Schema.PlanFeature do
  use Ecto.Schema
  import Ecto.Changeset

  schema "plan_features" do
    belongs_to :plan, Licentio.Schema.Plan
    belongs_to :feature, Licentio.Schema.Feature

    field :value, :integer
    field :is_active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @required [:plan_id, :feature_id]
  @optional [:value, :is_active]

  def changeset(plan_feature, attrs) do
    plan_feature
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> unique_constraint(:feature_id,
      name: :plan_features_plan_id_feature_id_index,
      message: "feature already added to this plan"
    )
    |> validate_number(:value, greater_than_or_equal_to: 0)
  end
end
