module Products
  # Fills in the shelf life of products no kitchen has met before.
  #
  # Called while a capture is ingested, before its windows are worked out, so
  # the very first pack already gets the food's own numbers. Nothing here may
  # stop a capture: with no key, the stub, a refusal or a timeout the products
  # simply stay unknown and those packs use the category rule, as before.
  #
  # First answer wins. It is shared by every kitchen, so a bad one would spread;
  # Product.clean_place drops impossible numbers and Freshness::Estimator caps
  # high-risk food. Agreement across several answers, as the shared dictionary
  # requires (ProductAlias), is a later step.
  class LearnShelfLife < ApplicationService
    MAX_PER_CALL = 25

    def initialize(products:, household: nil)
      @products = Array(products).compact.uniq
      @household = household
    end

    def call
      return [] unless Ai::Config.live?

      unknown = @products.reject { |product| product.shelf_life.present? }.first(MAX_PER_CALL)
      return [] if unknown.empty?

      answers = Ai::ShelfLifeReader.call(products: unknown.map(&:key), household: @household)
      unknown.filter_map { |product| remember(product, answers[product.key]) }
    rescue Ai::Client::Error => e
      Rails.logger.warn("shelf life not learned: #{e.class}: #{e.message}")
      []
    end

    private

    def remember(product, answer)
      return nil unless answer.is_a?(Hash)

      places = Product::PLACES.index_with { |place| Product.clean_place(answer[place])&.stringify_keys }
      return nil if places.values.none?

      # Only where nothing is stored yet: a concurrent capture may have won.
      updated = Product.where(id: product.id, shelf_life: nil).update_all(shelf_life: places, updated_at: Time.current)
      product.reload if updated.positive?
      product
    end
  end
end
