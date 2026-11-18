# Dictionary keys and dictation phrases now fold umlauts ("hähnchen" == "haehnchen"), so existing
# rows are re-keyed with ProductAlias.normalize_key. Where two rows of one
# layer now share a key ("käse" and "kaese" in the seeds), the older row stays
# and the newer duplicate goes: both said the same thing.
class RenormalizeProductAliasKeys < ActiveRecord::Migration[8.1]
  def up
    ProductAlias.reset_column_information
    ProductAlias.order(:id).find_each do |entry|
      key = ProductAlias.normalize_key(entry.raw_text)
      next if key == entry.raw_text

      taken = ProductAlias.where(household_id: entry.household_id, merchant: entry.merchant, raw_text: key)
                          .where.not(id: entry.id).exists?
      taken ? entry.delete : entry.update_columns(raw_text: key)
    end

    # Dictation phrases are compared with the same key, so they move with it.
    VocabularyEntry.reset_column_information
    VocabularyEntry.order(:id).find_each do |entry|
      key = ProductAlias.normalize_key(entry.phrase)
      next if key == entry.phrase

      taken = VocabularyEntry.where(household_id: entry.household_id, kind: entry.kind, phrase: key)
                             .where.not(id: entry.id).exists?
      taken ? entry.delete : entry.update_columns(phrase: key)
    end
  end

  def down
    # Folded keys still match: nothing to put back.
  end
end
