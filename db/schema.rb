# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_08_215159) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ai_calls", force: :cascade do |t|
    t.integer "attempt", default: 0, null: false
    t.float "audio_seconds", default: 0.0, null: false
    t.integer "cost_micros", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "duration_ms", default: 0, null: false
    t.string "error_message"
    t.integer "household_id"
    t.integer "input_tokens", default: 0, null: false
    t.string "model", null: false
    t.integer "output_tokens", default: 0, null: false
    t.string "provider", default: "openai", null: false
    t.string "purpose", null: false
    t.boolean "success", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_ai_calls_on_household_id"
    t.index ["provider", "created_at"], name: "index_ai_calls_on_provider_and_created_at"
    t.index ["purpose", "created_at"], name: "index_ai_calls_on_purpose_and_created_at"
  end

  create_table "captures", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "error_message"
    t.integer "household_id", null: false
    t.integer "line_count", default: 0, null: false
    t.string "merchant"
    t.float "parse_confidence"
    t.date "purchased_on"
    t.text "raw_response"
    t.string "source", null: false
    t.string "status", default: "pending", null: false
    t.text "transcript"
    t.datetime "updated_at", null: false
    t.index ["household_id", "created_at"], name: "index_captures_on_household_id_and_created_at"
    t.index ["household_id"], name: "index_captures_on_household_id"
  end

  create_table "households", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_seen_at"
    t.string "locale", default: "en", null: false
    t.string "name", null: false
    t.string "timezone", default: "Europe/Berlin", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["token"], name: "index_households_on_token", unique: true
    t.index ["uuid"], name: "index_households_on_uuid", unique: true
  end

  create_table "item_events", force: :cascade do |t|
    t.datetime "at", null: false
    t.datetime "created_at", null: false
    t.integer "household_id", null: false
    t.integer "item_id", null: false
    t.string "kind", null: false
    t.text "meta"
    t.datetime "updated_at", null: false
    t.index ["household_id", "kind", "at"], name: "index_item_events_on_household_id_and_kind_and_at"
    t.index ["household_id"], name: "index_item_events_on_household_id"
    t.index ["item_id"], name: "index_item_events_on_item_id"
  end

  create_table "items", force: :cascade do |t|
    t.date "acquired_on", null: false
    t.string "canonical_name", null: false
    t.integer "capture_id"
    t.string "category", default: "unknown", null: false
    t.float "confidence", default: 0.3, null: false
    t.datetime "created_at", null: false
    t.string "date_label_type", default: "none", null: false
    t.date "date_label_value"
    t.string "display_name", null: false
    t.integer "household_id", null: false
    t.integer "lock_version", default: 0, null: false
    t.date "opened_on"
    t.decimal "quantity", precision: 8, scale: 2
    t.float "quantity_confidence"
    t.string "raw_text"
    t.datetime "resolved_at"
    t.date "snoozed_until"
    t.string "state", default: "active", null: false
    t.string "storage", default: "fridge", null: false
    t.datetime "storage_changed_at"
    t.string "unit"
    t.datetime "updated_at", null: false
    t.date "window_end", null: false
    t.date "window_start", null: false
    t.index ["capture_id"], name: "index_items_on_capture_id"
    t.index ["household_id", "canonical_name"], name: "index_items_on_household_id_and_canonical_name"
    t.index ["household_id", "state", "window_end"], name: "index_items_on_household_id_and_state_and_window_end"
    t.index ["household_id"], name: "index_items_on_household_id"
  end

  create_table "memo_items", force: :cascade do |t|
    t.string "canonical_name"
    t.datetime "created_at", null: false
    t.boolean "done", default: false, null: false
    t.datetime "done_at"
    t.integer "household_id", null: false
    t.string "name", null: false
    t.string "note"
    t.integer "position", default: 0, null: false
    t.string "source", default: "text", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "done", "position"], name: "index_memo_items_on_household_id_and_done_and_position"
    t.index ["household_id"], name: "index_memo_items_on_household_id"
  end

  create_table "product_aliases", force: :cascade do |t|
    t.string "canonical_name", null: false
    t.string "category", null: false
    t.datetime "created_at", null: false
    t.string "emoji"
    t.string "merchant"
    t.string "raw_text", null: false
    t.boolean "seeded", default: false, null: false
    t.datetime "updated_at", null: false
    t.integer "votes", default: 1, null: false
    t.index ["canonical_name"], name: "index_product_aliases_on_canonical_name"
    t.index ["raw_text", "merchant"], name: "index_product_aliases_on_raw_text_and_merchant", unique: true
  end

  create_table "shelf_life_rules", force: :cascade do |t|
    t.string "category", null: false
    t.integer "consume_p50", null: false
    t.datetime "created_at", null: false
    t.integer "days_p50", null: false
    t.integer "days_p90", null: false
    t.boolean "high_risk", default: false, null: false
    t.string "storage", null: false
    t.datetime "updated_at", null: false
    t.index ["category", "storage"], name: "index_shelf_life_rules_on_category_and_storage", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ai_calls", "households"
  add_foreign_key "captures", "households"
  add_foreign_key "item_events", "households"
  add_foreign_key "item_events", "items"
  add_foreign_key "items", "captures"
  add_foreign_key "items", "households"
  add_foreign_key "memo_items", "households"
end
