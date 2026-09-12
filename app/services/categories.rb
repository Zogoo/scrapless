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
                  gouda cheddar mozzarella feta skyr kefir egg eier],
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

  # Short keywords must match a whole word; longer ones may match inside one.
  #
  # German compounds make substring matching genuinely useful — "brot" has to
  # find "Vollkornbrot" — but it is dangerous for two- and three-letter
  # keywords. Observed live: "WEIZENBRÖTCHEN 6ER" came back as *dairy*, because
  # the dairy keyword "ei" sits inside "weizenbrötchen", which gave bread a
  # 14-day fridge window. That is precisely the false-expiry failure doc 3 §3.4
  # says killed Fridgely.
  WHOLE_WORD_BELOW = 4

  module_function

  def guess(text)
    key = text.to_s.downcase
    words = key.scan(/[[:alnum:]äöüß]+/)

    KEYWORDS.each do |category, keywords|
      return category if keywords.any? { |k| matches?(k, key, words) }
    end
    "other"
  end

  def matches?(keyword, key, words)
    keyword.length < WHOLE_WORD_BELOW ? words.include?(keyword) : key.include?(keyword)
  end

  def storage_for(category) = DEFAULT_STORAGE.fetch(category, "pantry")

  def high_risk?(category) = HIGH_RISK.include?(category)

  def valid?(category) = NAMES.include?(category)

  def coerce(category) = valid?(category) ? category : "other"
end
