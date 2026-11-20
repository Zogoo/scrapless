# Seeds the two reference tables the freshness engine and the parser read from.
# Idempotent: safe to re-run on every deploy.

# --- Shelf life -------------------------------------------------------------
# days_p50/p90 model spoilage; consume_p50 models how long a household takes to
# eat the thing. They are different curves, and using the first for both is the
# mistake that makes an app warn you about food you finished on Tuesday.
#
# Freezer numbers are looked up per category, never derived by multiplying a
# fridge window: frozen chicken is months, not eight times two days.
rules = {
  #                 fridge            freezer            pantry
  "produce" =>    [ [ 5,   9,  5 ], [ 180, 300,  90 ], [   4,   8,   5 ] ],
  "dairy" =>      [ [ 8,  14,  6 ], [  60,  90,  60 ], [  60, 180,  30 ] ],
  # Meat or fish in the cupboard is raw food left out — tins are "pantry" (see
  # Categories::GUIDE) — and goes off within hours (USDA FSIS, "Danger Zone").
  # It used to get 365–730 days: a kitchen saw "Meat — fine for about 24 months".
  "meat_fish" =>  [ [ 2,   3,  2 ], [ 120, 270,  60 ], [   1,   1,  1 ] ],
  "bakery" =>     [ [ 5,   8,  4 ], [  60,  90,  45 ], [   3,   5,   3 ] ],
  "deli" =>       [ [ 4,   7,  4 ], [  30,  60,  30 ], [  30,  60,  30 ] ],
  "prepared" =>   [ [ 2,   3,  2 ], [  60,  90,  45 ], [   5,  10,   5 ] ],
  "frozen" =>     [ [ 1,   2,  1 ], [ 120, 240,  90 ], [   1,   1,   1 ] ],
  "pantry" =>     [ [ 30,  90, 30 ], [ 180, 365,  90 ], [ 180, 365,  60 ] ],
  "drinks" =>     [ [ 10,  20,  7 ], [  90, 180,  60 ], [ 120, 365,  20 ] ],
  # Food we cannot place gets doc 3's wide "about a week?" band, in the
  # cupboard too. It used to get up to 180 days there, so anything the parser
  # did not recognise — scallops, cold cuts, soy yoghurt — sat "fine for about 6
  # months". Too short means an early nudge; too long means food that rots
  # unseen. The freezer keeps its months: freezing really does stop the clock.
  "other" =>      [ [ 6,  10,  5 ], [ 120, 240,  90 ], [   6,  10,  5 ] ],
  "unknown" =>    [ [ 6,  10,  5 ], [ 120, 240,  90 ], [   6,  10,  5 ] ]
}

rules.each do |category, (fridge, freezer, pantry)|
  { "fridge" => fridge, "freezer" => freezer, "pantry" => pantry }.each do |storage, (p50, p90, consume)|
    rule = ShelfLifeRule.find_or_initialize_by(category: category, storage: storage)
    rule.update!(days_p50: p50, days_p90: p90, consume_p50: consume,
                 high_risk: Categories.high_risk?(category) && storage != "freezer")
  end
end

# --- Receipt dictionary -----------------------------------------------------
# The cold start for the compounding asset. German till receipts print a house
# abbreviation, not a product name, and these ten chains cover roughly 80% of
# German grocery spend (doc 0). Every user correction adds to this table.
#
# The last column is the product (Product): one English key per food, so
# "milch" and "milk" are known to be the same thing whatever the language.
aliases = [
  # produce
  [ "brokkoli", "Brokkoli", "produce", "🥦", "broccoli" ],
  [ "broccoli", "Broccoli", "produce", "🥦", "broccoli" ],
  [ "babyspinat", "Babyspinat", "produce", "🥬", "baby spinach" ],
  [ "spinat", "Spinat", "produce", "🥬", "spinach" ],
  [ "spinach", "Spinach", "produce", "🥬", "spinach" ],
  [ "salatgurke", "Salatgurke", "produce", "🥒", "cucumber" ],
  [ "gurk sal stck", "Salatgurke", "produce", "🥒", "cucumber" ],
  [ "tomaten", "Tomaten", "produce", "🍅", "tomato" ],
  [ "rispentomaten", "Rispentomaten", "produce", "🍅", "tomato" ],
  [ "karotten", "Karotten", "produce", "🥕", "carrot" ],
  [ "moehren", "Möhren", "produce", "🥕", "carrot" ],
  [ "kartoffeln", "Kartoffeln", "produce", "🥔", "potato" ],
  [ "zwiebeln", "Zwiebeln", "produce", "🧅", "onion" ],
  [ "paprika", "Paprika", "produce", "🫑", "bell pepper" ],
  [ "bananen", "Bananen", "produce", "🍌", "banana" ],
  [ "bananas", "Bananas", "produce", "🍌", "banana" ],
  [ "aepfel", "Äpfel", "produce", "🍎", "apple" ],
  [ "apples", "Apples", "produce", "🍎", "apple" ],
  [ "kopfsalat", "Kopfsalat", "produce", "🥬", "lettuce" ],
  [ "avocado", "Avocado", "produce", "🥑", "avocado" ],
  [ "champignons", "Champignons", "produce", "🍄", "mushroom" ],
  [ "zucchini", "Zucchini", "produce", "🥒", "zucchini" ],
  # dairy
  [ "h milch", "H-Milch", "dairy", "🥛", "uht milk" ],
  [ "frischmilch", "Frischmilch", "dairy", "🥛", "milk" ],
  [ "milch", "Milch", "dairy", "🥛", "milk" ],
  [ "milk", "Milk", "dairy", "🥛", "milk" ],
  [ "butter", "Butter", "dairy", "🧈", "butter" ],
  [ "joghurt", "Joghurt", "dairy", "🥣", "yogurt" ],
  [ "yoghurt", "Yoghurt", "dairy", "🥣", "yogurt" ],
  [ "quark", "Quark", "dairy", "🥣", "quark" ],
  [ "schlagsahne", "Schlagsahne", "dairy", "🥛", "whipping cream" ],
  [ "gouda", "Gouda", "dairy", "🧀", "gouda" ],
  [ "cheddar", "Cheddar", "dairy", "🧀", "cheddar" ],
  [ "mozzarella", "Mozzarella", "dairy", "🧀", "mozzarella" ],
  [ "frischkaese", "Frischkäse", "dairy", "🧀", "cream cheese" ],
  [ "eier", "Eier", "dairy", "🥚", "egg" ],
  [ "eggs", "Eggs", "dairy", "🥚", "egg" ],
  # meat and fish
  [ "haehnchenschenkel", "Hähnchenschenkel", "meat_fish", "🍗", "chicken thigh" ],
  [ "haehnchenbrust", "Hähnchenbrust", "meat_fish", "🍗", "chicken breast" ],
  [ "chicken", "Chicken", "meat_fish", "🍗", "chicken" ],
  [ "hackfleisch", "Hackfleisch", "meat_fish", "🥩", "minced meat" ],
  [ "rinderhack", "Rinderhack", "meat_fish", "🥩", "minced beef" ],
  [ "lachsfilet", "Lachsfilet", "meat_fish", "🐟", "salmon" ],
  [ "salmon", "Salmon", "meat_fish", "🐟", "salmon" ],
  [ "bratwurst", "Bratwurst", "meat_fish", "🌭", "bratwurst" ],
  # bakery
  [ "weizenbroetchen", "Weizenbrötchen", "bakery", "🥖", "bread roll" ],
  [ "broetchen", "Brötchen", "bakery", "🥖", "bread roll" ],
  [ "vollkornbrot", "Vollkornbrot", "bakery", "🍞", "wholemeal bread" ],
  [ "brot", "Brot", "bakery", "🍞", "bread" ],
  [ "bread", "Bread", "bakery", "🍞", "bread" ],
  [ "toast", "Toast", "bakery", "🍞", "toast bread" ],
  # deli
  [ "kochschinken", "Kochschinken", "deli", "🍖", "cooked ham" ],
  [ "salami", "Salami", "deli", "🍖", "salami" ],
  [ "hummus", "Hummus", "deli", "🥣", "hummus" ],
  # pantry and drinks
  [ "spaetzle", "Spätzle", "pantry", "🍝", "spaetzle" ],
  [ "spätzle", "Spätzle", "pantry", "🍝", "spaetzle" ],
  [ "spaghetti", "Spaghetti", "pantry", "🍝", "spaghetti" ],
  [ "nudeln", "Nudeln", "pantry", "🍝", "pasta" ],
  [ "pasta", "Pasta", "pantry", "🍝", "pasta" ],
  [ "reis", "Reis", "pantry", "🍚", "rice" ],
  [ "rice", "Rice", "pantry", "🍚", "rice" ],
  [ "olivenoel", "Olivenöl", "pantry", "🫒", "olive oil" ],
  [ "passierte tomaten", "Passierte Tomaten", "pantry", "🥫", "passata" ],
  [ "kaffee", "Kaffee", "drinks", "☕", "coffee" ],
  [ "coffee", "Coffee", "drinks", "☕", "coffee" ],
  [ "orangensaft", "Orangensaft", "drinks", "🧃", "orange juice" ],
  [ "mineralwasser", "Mineralwasser", "drinks", "💧", "mineral water" ],
  # frozen
  [ "tk erbsen", "TK-Erbsen", "frozen", "🧊", "frozen peas" ],
  [ "tiefkuehlpizza", "Tiefkühlpizza", "frozen", "🍕", "frozen pizza" ],
  # The tap grid sends its labels (capture.ts TAP_GRID, in each locale file),
  # so every one must resolve for free.
  [ "käse", "Käse", "dairy", "🧀", "cheese" ],
  [ "kaese", "Käse", "dairy", "🧀", "cheese" ],
  [ "äpfel", "Äpfel", "produce", "🍎", "apple" ],
  [ "hähnchen", "Hähnchen", "meat_fish", "🍗", "chicken" ],
  [ "haehnchen", "Hähnchen", "meat_fish", "🍗", "chicken" ],
  [ "fisch", "Fisch", "meat_fish", "🐟", "fish" ],
  [ "salat", "Salat", "produce", "🥗", "lettuce" ],
  # ...and their English labels, on the same products.
  [ "cheese", "Cheese", "dairy", "🧀", "cheese" ],
  [ "carrots", "Carrots", "produce", "🥕", "carrot" ],
  [ "tomatoes", "Tomatoes", "produce", "🍅", "tomato" ],
  [ "potatoes", "Potatoes", "produce", "🥔", "potato" ],
  [ "onions", "Onions", "produce", "🧅", "onion" ],
  [ "mince", "Mince", "meat_fish", "🥩", "minced meat" ],
  [ "fish", "Fish", "meat_fish", "🐟", "fish" ],
  [ "salad", "Salad", "produce", "🥗", "lettuce" ]
]

aliases.each do |raw, canonical, category, emoji, product|
  entry = ProductAlias.shared.find_or_initialize_by(raw_text: ProductAlias.normalize_key(raw), merchant: nil)
  entry.update!(canonical_name: canonical, category: category, emoji: emoji, seeded: true, source: "seed",
                product: Product.for(product, category: category))
end

puts "seeded #{ShelfLifeRule.count} shelf-life rules and #{ProductAlias.count} dictionary entries"
