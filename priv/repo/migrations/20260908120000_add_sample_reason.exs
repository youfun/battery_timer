defmodule BatteryTimer.Repo.Migrations.AddSampleReason do
  use Ecto.Migration

  def change do
    alter table(:battery_samples) do
      add :reason, :string, null: false, default: "manual"
    end
  end
end
