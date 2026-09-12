class CreateAiCalls < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_calls do |t|
      t.references :household, foreign_key: true
      # receipt_extract | shelf_photo_extract | transcribe | text_parse
      t.string  :purpose, null: false
      t.string  :model,   null: false
      t.integer :input_tokens,  null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.float   :audio_seconds, null: false, default: 0.0
      # Micro-dollars: an integer, because floats do not add up over a million rows.
      t.integer :cost_micros, null: false, default: 0
      t.integer :duration_ms, null: false, default: 0
      t.boolean :success, null: false, default: true
      t.string  :error_message

      t.timestamps
    end

    add_index :ai_calls, %i[purpose created_at]
  end
end
