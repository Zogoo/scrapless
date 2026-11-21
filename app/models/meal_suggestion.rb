# The recipes already written for one meal, in one kitchen, on one day.
class MealSuggestion < ApplicationRecord
  # "brotbox" is the next school day's lunchbox, stored under that day.
  MEALS = %w[breakfast lunch dinner brotbox].freeze

  belongs_to :household

  validates :meal, inclusion: { in: MEALS }
  validates :served_on, :locale, :body, presence: true
  validates :meal, uniqueness: { scope: %i[household_id served_on locale] }

  def payload
    JSON.parse(body).map { |recipe| recipe.deep_symbolize_keys }
  end
end
