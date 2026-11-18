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

ActiveRecord::Schema[8.1].define(version: 2026_11_18_215416) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ai_calls", force: :cascade do |t|
    t.integer "household_id"
    t.string "purpose", null: false
    t.string "model", null: false
    t.integer "input_tokens", default: 0, null: false
    t.integer "output_tokens", default: 0, null: false
    t.float "audio_seconds", default: 0.0, null: false
    t.integer "cost_micros", default: 0, null: false
    t.integer "duration_ms", default: 0, null: false
    t.boolean "success", default: true, null: false
    t.string "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "provider", default: "openai", null: false
    t.integer "attempt", default: 0, null: false
    t.index ["household_id"], name: "index_ai_calls_on_household_id"
    t.index ["provider", "created_at"], name: "index_ai_calls_on_provider_and_created_at"
    t.index ["purpose", "created_at"], name: "index_ai_calls_on_purpose_and_created_at"
  end

  create_table "captures", force: :cascade do |t|
    t.integer "household_id", null: false
    t.string "source", null: false
    t.string "status", default: "pending", null: false
    t.string "merchant"
    t.date "purchased_on"
    t.float "parse_confidence"
    t.text "transcript"
    t.text "raw_response"
    t.string "error_message"
    t.integer "line_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "added_by_name"
    t.index ["household_id", "created_at"], name: "index_captures_on_household_id_and_created_at"
    t.index ["household_id"], name: "index_captures_on_household_id"
  end

  create_table "households", force: :cascade do |t|
    t.string "uuid", null: false
    t.string "token", null: false
    t.string "name", null: false
    t.string "timezone", default: "Europe/Berlin", null: false
    t.string "locale", default: "en", null: false
    t.datetime "last_seen_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "join_code", null: false
    t.integer "alerts_per_week", default: 1, null: false
    t.index ["join_code"], name: "index_households_on_join_code", unique: true
    t.index ["token"], name: "index_households_on_token", unique: true
    t.index ["uuid"], name: "index_households_on_uuid", unique: true
  end

  create_table "item_events", force: :cascade do |t|
    t.integer "item_id", null: false
    t.integer "household_id", null: false
    t.string "kind", null: false
    t.datetime "at", null: false
    t.text "meta"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "kind", "at"], name: "index_item_events_on_household_id_and_kind_and_at"
    t.index ["household_id"], name: "index_item_events_on_household_id"
    t.index ["item_id"], name: "index_item_events_on_item_id"
  end

  create_table "items", force: :cascade do |t|
    t.integer "household_id", null: false
    t.integer "capture_id"
    t.string "display_name", null: false
    t.string "canonical_name", null: false
    t.string "category", default: "unknown", null: false
    t.string "raw_text"
    t.decimal "quantity", precision: 8, scale: 2
    t.string "unit"
    t.float "quantity_confidence"
    t.string "storage", default: "fridge", null: false
    t.datetime "storage_changed_at"
    t.date "acquired_on", null: false
    t.date "window_start", null: false
    t.date "window_end", null: false
    t.float "confidence", default: 0.3, null: false
    t.date "opened_on"
    t.string "date_label_type", default: "none", null: false
    t.date "date_label_value"
    t.string "state", default: "active", null: false
    t.datetime "resolved_at"
    t.date "snoozed_until"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "added_by_name"
    t.float "amount_left", default: 1.0, null: false
    t.integer "product_id"
    t.index ["capture_id"], name: "index_items_on_capture_id"
    t.index ["household_id", "canonical_name"], name: "index_items_on_household_id_and_canonical_name"
    t.index ["household_id", "state", "window_end"], name: "index_items_on_household_id_and_state_and_window_end"
    t.index ["household_id"], name: "index_items_on_household_id"
    t.index ["product_id"], name: "index_items_on_product_id"
  end

  create_table "meal_suggestions", force: :cascade do |t|
    t.integer "household_id", null: false
    t.string "meal", null: false
    t.date "served_on", null: false
    t.string "locale", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "meal", "served_on"], name: "index_meal_suggestions_on_household_meal_and_day", unique: true
    t.index ["household_id"], name: "index_meal_suggestions_on_household_id"
  end

  create_table "memo_items", force: :cascade do |t|
    t.integer "household_id", null: false
    t.string "name", null: false
    t.string "canonical_name"
    t.string "note"
    t.string "source", default: "text", null: false
    t.boolean "done", default: false, null: false
    t.datetime "done_at"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "added_by_name"
    t.index ["household_id", "done", "position"], name: "index_memo_items_on_household_id_and_done_and_position"
    t.index ["household_id"], name: "index_memo_items_on_household_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.integer "household_id", null: false
    t.string "iso_week", null: false
    t.integer "slot", null: false
    t.date "sent_on", null: false
    t.json "item_ids", default: [], null: false
    t.datetime "opened_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "iso_week", "slot"], name: "index_notifications_on_household_id_and_iso_week_and_slot", unique: true
    t.index ["household_id", "sent_on"], name: "index_notifications_on_household_id_and_sent_on", unique: true
    t.index ["household_id"], name: "index_notifications_on_household_id"
  end

  create_table "product_aliases", force: :cascade do |t|
    t.string "raw_text", null: false
    t.string "canonical_name", null: false
    t.string "category", null: false
    t.string "merchant"
    t.string "emoji"
    t.integer "votes", default: 1, null: false
    t.boolean "seeded", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "household_id"
    t.integer "product_id"
    t.string "source", default: "correction", null: false
    t.string "storage"
    t.index ["canonical_name"], name: "index_product_aliases_on_canonical_name"
    t.index ["household_id", "raw_text", "merchant"], name: "index_product_aliases_on_household_raw_text_merchant", unique: true
    t.index ["household_id"], name: "index_product_aliases_on_household_id"
    t.index ["product_id"], name: "index_product_aliases_on_product_id"
    t.index ["raw_text", "merchant"], name: "index_product_aliases_on_raw_text_and_merchant"
  end

  create_table "products", force: :cascade do |t|
    t.string "key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_products_on_key", unique: true
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.integer "household_id", null: false
    t.string "endpoint", null: false
    t.string "p256dh", null: false
    t.string "auth", null: false
    t.string "locale", default: "en", null: false
    t.datetime "last_delivered_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["endpoint"], name: "index_push_subscriptions_on_endpoint", unique: true
    t.index ["household_id"], name: "index_push_subscriptions_on_household_id"
  end

  create_table "shelf_life_rules", force: :cascade do |t|
    t.string "category", null: false
    t.string "storage", null: false
    t.integer "days_p50", null: false
    t.integer "days_p90", null: false
    t.integer "consume_p50", null: false
    t.boolean "high_risk", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category", "storage"], name: "index_shelf_life_rules_on_category_and_storage", unique: true
  end

  create_table "suggestion_dismissals", force: :cascade do |t|
    t.integer "household_id", null: false
    t.string "canonical_name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "canonical_name"], name: "index_suggestion_dismissals_on_household_id_and_canonical_name", unique: true
    t.index ["household_id"], name: "index_suggestion_dismissals_on_household_id"
  end

  create_table "vocabulary_entries", force: :cascade do |t|
    t.integer "household_id", null: false
    t.string "kind", null: false
    t.string "phrase", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "kind", "phrase"], name: "index_vocabulary_entries_on_household_id_and_kind_and_phrase", unique: true
    t.index ["household_id"], name: "index_vocabulary_entries_on_household_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ai_calls", "households"
  add_foreign_key "captures", "households"
  add_foreign_key "item_events", "households"
  add_foreign_key "item_events", "items"
  add_foreign_key "items", "captures"
  add_foreign_key "items", "households"
  add_foreign_key "items", "products"
  add_foreign_key "meal_suggestions", "households"
  add_foreign_key "memo_items", "households"
  add_foreign_key "notifications", "households"
  add_foreign_key "product_aliases", "households"
  add_foreign_key "product_aliases", "products"
  add_foreign_key "push_subscriptions", "households"
  add_foreign_key "suggestion_dismissals", "households"
  add_foreign_key "vocabulary_entries", "households"
end
