module Items
  # Gives a product to food that has none, so it joins the same Kitchen line as
  # the same food captured later.
  #
  # Products arrived in #65 (20261118214835_add_product_to_items) without
  # filling in the items already in kitchens. Eggs from before then were keyed
  # by name ("fridge:eier"), every egg since by product, so one fridge showed
  # two egg lines. Also picks up food captured without a model, whose
  # dictionary entry has since learned its product.
  #
  # Exact dictionary matches only, this kitchen's entries first: a fuzzy guess
  # here would silently merge two different foods.
  class BackfillProducts < ApplicationService
    def initialize(scope: Item.where(product_id: nil))
      @scope = scope
    end

    def call
      filled = 0
      @scope.includes(:household).find_each do |item|
        product_id = product_for(item)
        next unless product_id

        item.update_columns(product_id: product_id)
        filled += 1
      end
      filled
    end

    private

    def product_for(item)
      names = [ item.raw_text, Copy.bare_name(item), item.canonical_name ].compact_blank
      ProductAlias.lookup(names, household: item.household, fuzzy: false)&.product_id
    end
  end
end
