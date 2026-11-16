# One row per phone that said yes to notifications. The endpoint is the push
# service's address for that browser; p256dh and auth are its encryption keys
# (RFC 8291). Endpoints run to several hundred characters.
class CreatePushSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :push_subscriptions do |t|
      t.references :household, null: false, foreign_key: true
      t.string :endpoint, null: false
      t.string :p256dh, null: false
      t.string :auth, null: false
      t.string :locale, null: false, default: "en"
      t.datetime :last_delivered_at

      t.timestamps
    end
    add_index :push_subscriptions, :endpoint, unique: true
  end
end
