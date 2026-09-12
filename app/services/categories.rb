# The category vocabulary, shared by the shelf-life table, the parsers and the
# seed data. Deliberately small: ten buckets that behave differently in a fridge,
# not a taxonomy.
module Categories
  NAMES = %w[produce dairy meat_fish bakery deli prepared frozen pantry drinks other].freeze

  HIGH_RISK = %w[meat_fish prepared deli].freeze

  DEFAULT_STORAGE = {
    "produce" => "fridge", "dairy" => "fridge", "meat_fish" => "fridge",
    "bakery" => "pantry", "deli" => "fridge", "prepared" => "fridge",
    "frozen" => "freezer", "pantry" => "pantry", "drinks" => "pantry",
    "other" => "pantry"
  }.freeze

  # Keyword hints in both launch languages. This is a cheap first pass, not a
  # classifier: a miss costs one nano-tier call, not a wrong answer.
  KEYWORDS = {
    "produce" => %w[apple banana broccoli brokkoli spinach spinat carrot karotte salad salat tomato tomate
                    cucumber gurke pepper paprika onion zwiebel potato kartoffel lettuce berry beere
                    orange lemon zitrone avocado mushroom pilz courgette zucchini kohl cabbage lauch leek],
    "dairy" => %w[milk milch cheese käse kaese yoghurt joghurt yogurt butter cream sahne quark
                  gouda cheddar mozzarella feta skyr kefir egg eier ei],
    "meat_fish" => %w[chicken hähnchen haehnchen hahnchen beef rind pork schwein mince hack sausage wurst
                      bacon speck fish fisch salmon lachs prawn garnele turkey pute schnitzel steak],
    "bakery" => %w[bread brot roll brötchen broetchen baguette croissant bun cake kuchen toast brezel],
    "deli" => %w[ham schinken salami olive hummus antipasti aufschnitt],
    "prepared" => %w[pizza salad-bowl soup suppe curry lasagne sandwich sushi fertiggericht leftovers reste],
    "frozen" => %w[frozen tiefkühl tiefkuehl tk ice cream eis pommes],
    "pantry" => %w[rice reis pasta nudel flour mehl sugar zucker oil öl oel vinegar essig sauce
                   bean bohne lentil linse tin dose can nuts nuss cereal müsli muesli honey honig],
    "drinks" => %w[water wasser juice saft beer bier wine wein cola coffee kaffee tea tee limonade]
  }.freeze

  module_function

  def guess(text)
    key = text.to_s.downcase
    KEYWORDS.each do |category, words|
      return category if words.any? { |w| key.include?(w) }
    end
    "other"
  end

  def storage_for(category) = DEFAULT_STORAGE.fetch(category, "pantry")

  def high_risk?(category) = HIGH_RISK.include?(category)

  def valid?(category) = NAMES.include?(category)

  def coerce(category) = valid?(category) ? category : "other"
end
