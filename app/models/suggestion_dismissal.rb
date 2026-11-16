# A Shop suggestion this kitchen asked us to stop making.
class SuggestionDismissal < ApplicationRecord
  belongs_to :household

  validates :canonical_name, presence: true, length: { maximum: 120 },
                             uniqueness: { scope: :household_id }

  normalizes :canonical_name, with: ->(name) { name.to_s.strip.downcase.presence }
end
