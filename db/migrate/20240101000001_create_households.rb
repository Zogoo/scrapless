class CreateHouseholds < ActiveRecord::Migration[8.1]
  def change
    create_table :households do |t|
      t.string :uuid,     null: false
      t.string :token,    null: false
      t.string :name,     null: false
      t.string :timezone, null: false, default: "Europe/Berlin"
      t.string :locale,   null: false, default: "en"
      t.datetime :last_seen_at

      t.timestamps
    end

    add_index :households, :uuid,  unique: true
    add_index :households, :token, unique: true
  end
end
