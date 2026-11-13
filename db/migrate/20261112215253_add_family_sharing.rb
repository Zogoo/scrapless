class AddFamilySharing < ActiveRecord::Migration[8.1]
  def change
    add_column :captures, :added_by_name, :string
    add_column :items, :added_by_name, :string
    add_column :memo_items, :added_by_name, :string

    add_column :households, :join_code, :string
    reversible { |dir| dir.up { backfill_join_codes } }
    change_column_null :households, :join_code, false
    add_index :households, :join_code, unique: true
  end

  private

  # Existing fridges were created before there was anything to share. The code
  # is not the bearer token, and it has to be unique, so it cannot be a default.
  def backfill_join_codes
    taken = select_values("SELECT join_code FROM households WHERE join_code IS NOT NULL").to_set

    select_values("SELECT id FROM households WHERE join_code IS NULL").each do |id|
      code = loop do
        candidate = SecureRandom.urlsafe_base64(16)
        break candidate unless taken.include?(candidate)
      end
      taken << code
      update(<<~SQL.squish)
        UPDATE households
           SET join_code = #{connection.quote(code)}
         WHERE id = #{Integer(id)}
      SQL
    end
  end
end
