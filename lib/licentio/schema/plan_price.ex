defmodule Licentio.Schema.PlanPrice do
  use Ecto.Schema
  import Ecto.Changeset

  @duration_units ~w(day month year forever)
  def duration_units, do: @duration_units

  schema "plan_prices" do
    belongs_to :plan, Licentio.Schema.Plan

    field :duration_unit, :string
    field :duration_value, :integer
    field :price, :decimal
    field :currency, :string, default: "USD"
    field :is_active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @required [:plan_id, :duration_unit, :price]
  @optional [:duration_value, :currency, :is_active]

  def changeset(plan_price, attrs) do
    plan_price
      |> cast(attrs, @required ++ @optional)
      |> validate_required(@required)
      |> validate_inclusion(:duration_unit, @duration_units)
      |> validate_number(:price, greater_than_or_equal_to: 0)
      |> validate_length(:currency, is: 3, message: "must be a 3-letter currency code")
      |> validate_duration()
  end

  defp validate_duration(changeset) do
    case get_field(changeset, :duration_unit) do
      "forever" ->
        if get_field(changeset, :duration_value) do
          add_error(changeset, :duration_value, "must be empty when duration is forever")
        else
          changeset
        end

      _ ->
        changeset
          |> validate_required([:duration_value], message: "is required for non-forever durations")
          |> validate_number(:duration_value, greater_than: 0)
    end
  end
end
