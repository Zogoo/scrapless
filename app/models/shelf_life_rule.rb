# Global shelf-life table. `days_*` model spoilage; `consume_p50` models how long
# a household takes to eat the thing, which is a different curve and the one that
# stops us alerting about food that was eaten on Tuesday.
class ShelfLifeRule < ApplicationRecord
  validates :category, :storage, presence: true
  validates :days_p50, :days_p90, :consume_p50,
            numericality: { only_integer: true, greater_than: 0 }

  def self.for(category, storage)
    find_by(category: category, storage: storage) ||
      find_by(category: "unknown", storage: storage)
  end
end
