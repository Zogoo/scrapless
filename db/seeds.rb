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
  "meat_fish" =>  [ [ 2,   3,  2 ], [ 120, 270,  60 ], [ 365, 730,  90 ] ],
  "bakery" =>     [ [ 5,   8,  4 ], [  60,  90,  45 ], [   3,   5,   3 ] ],
  "deli" =>       [ [ 4,   7,  4 ], [  30,  60,  30 ], [  30,  60,  30 ] ],
  "prepared" =>   [ [ 2,   3,  2 ], [  60,  90,  45 ], [   5,  10,   5 ] ],
  "frozen" =>     [ [ 1,   2,  1 ], [ 120, 240,  90 ], [   1,   1,   1 ] ],
  "pantry" =>     [ [ 30,  90, 30 ], [ 180, 365,  90 ], [ 180, 365,  60 ] ],
  "drinks" =>     [ [ 10,  20,  7 ], [  90, 180,  60 ], [ 120, 365,  20 ] ],
  "other" =>      [ [ 6,  10,  5 ], [ 120, 240,  90 ], [  60, 180,  45 ] ],
  "unknown" =>    [ [ 6,  10,  5 ], [ 120, 240,  90 ], [  60, 180,  45 ] ]
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
aliases = [
  # produce
  [ "brokkoli", "Brokkoli", "produce", "🥦" ],
  [ "broccoli", "Broccoli", "produce", "🥦" ],
  [ "babyspinat", "Babyspinat", "produce", "🥬" ],
  [ "spinat", "Spinat", "produce", "🥬" ],
  [ "spinach", "Spinach", "produce", "🥬" ],
  [ "salatgurke", "Salatgurke", "produce", "🥒" ],
  [ "gurk sal stck", "Salatgurke", "produce", "🥒" ],
  [ "tomaten", "Tomaten", "produce", "🍅" ],
  [ "rispentomaten", "Rispentomaten", "produce", "🍅" ],
  [ "karotten", "Karotten", "produce", "🥕" ],
  [ "moehren", "Möhren", "produce", "🥕" ],
  [ "kartoffeln", "Kartoffeln", "produce", "🥔" ],
  [ "zwiebeln", "Zwiebeln", "produce", "🧅" ],
  [ "paprika", "Paprika", "produce", "🫑" ],
  [ "bananen", "Bananen", "produce", "🍌" ],
  [ "bananas", "Bananas", "produce", "🍌" ],
  [ "aepfel", "Äpfel", "produce", "🍎" ],
  [ "apples", "Apples", "produce", "🍎" ],
  [ "kopfsalat", "Kopfsalat", "produce", "🥬" ],
  [ "avocado", "Avocado", "produce", "🥑" ],
  [ "champignons", "Champignons", "produce", "🍄" ],
  [ "zucchini", "Zucchini", "produce", "🥒" ],
  # dairy
  [ "h milch", "H-Milch", "dairy", "🥛" ],
  [ "frischmilch", "Frischmilch", "dairy", "🥛" ],
  [ "milch", "Milch", "dairy", "🥛" ],
  [ "milk", "Milk", "dairy", "🥛" ],
  [ "butter", "Butter", "dairy", "🧈" ],
  [ "joghurt", "Joghurt", "dairy", "🥣" ],
  [ "yoghurt", "Yoghurt", "dairy", "🥣" ],
  [ "quark", "Quark", "dairy", "🥣" ],
  [ "schlagsahne", "Schlagsahne", "dairy", "🥛" ],
  [ "gouda", "Gouda", "dairy", "🧀" ],
  [ "cheddar", "Cheddar", "dairy", "🧀" ],
  [ "mozzarella", "Mozzarella", "dairy", "🧀" ],
  [ "frischkaese", "Frischkäse", "dairy", "🧀" ],
  [ "eier", "Eier", "dairy", "🥚" ],
  [ "eggs", "Eggs", "dairy", "🥚" ],
  # meat and fish
  [ "haehnchenschenkel", "Hähnchenschenkel", "meat_fish", "🍗" ],
  [ "haehnchenbrust", "Hähnchenbrust", "meat_fish", "🍗" ],
  [ "chicken", "Chicken", "meat_fish", "🍗" ],
  [ "hackfleisch", "Hackfleisch", "meat_fish", "🥩" ],
  [ "rinderhack", "Rinderhack", "meat_fish", "🥩" ],
  [ "lachsfilet", "Lachsfilet", "meat_fish", "🐟" ],
  [ "salmon", "Salmon", "meat_fish", "🐟" ],
  [ "bratwurst", "Bratwurst", "meat_fish", "🌭" ],
  # bakery
  [ "weizenbroetchen", "Weizenbrötchen", "bakery", "🥖" ],
  [ "broetchen", "Brötchen", "bakery", "🥖" ],
  [ "vollkornbrot", "Vollkornbrot", "bakery", "🍞" ],
  [ "brot", "Brot", "bakery", "🍞" ],
  [ "bread", "Bread", "bakery", "🍞" ],
  [ "toast", "Toast", "bakery", "🍞" ],
  # deli
  [ "kochschinken", "Kochschinken", "deli", "🍖" ],
  [ "salami", "Salami", "deli", "🍖" ],
  [ "hummus", "Hummus", "deli", "🥣" ],
  # pantry and drinks
  [ "spaghetti", "Spaghetti", "pantry", "🍝" ],
  [ "nudeln", "Nudeln", "pantry", "🍝" ],
  [ "pasta", "Pasta", "pantry", "🍝" ],
  [ "reis", "Reis", "pantry", "🍚" ],
  [ "rice", "Rice", "pantry", "🍚" ],
  [ "olivenoel", "Olivenöl", "pantry", "🫒" ],
  [ "passierte tomaten", "Passierte Tomaten", "pantry", "🥫" ],
  [ "kaffee", "Kaffee", "drinks", "☕" ],
  [ "coffee", "Coffee", "drinks", "☕" ],
  [ "orangensaft", "Orangensaft", "drinks", "🧃" ],
  [ "mineralwasser", "Mineralwasser", "drinks", "💧" ],
  # frozen
  [ "tk erbsen", "TK-Erbsen", "frozen", "🧊" ],
  [ "tiefkuehlpizza", "Tiefkühlpizza", "frozen", "🍕" ]
]

aliases.each do |raw, canonical, category, emoji|
  entry = ProductAlias.find_or_initialize_by(raw_text: ProductAlias.normalize_key(raw), merchant: nil)
  entry.update!(canonical_name: canonical, category: category, emoji: emoji, seeded: true)
end

puts "seeded #{ShelfLifeRule.count} shelf-life rules and #{ProductAlias.count} dictionary entries"
