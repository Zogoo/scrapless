class AddProviderToAiCalls < ActiveRecord::Migration[8.1]
  def change
    # With a failover chain there is more than one bill, and "what did this cost"
    # is only answerable if each call says who served it.
    add_column :ai_calls, :provider, :string, null: false, default: "openai"
    # Which attempt in the chain this was: 0 = primary. A rising count here is
    # the signal that the primary is degraded.
    add_column :ai_calls, :attempt, :integer, null: false, default: 0

    add_index :ai_calls, %i[provider created_at]
  end
end
