# The one place that turns a number into a sentence.
#
# Centralised because the copy rules are product rules, not decoration: never
# "expired", never "abgelaufen", never a precise date we did not read off a
# label, and never a guilt frame (doc 4 §4.13). Scattering these strings through
# components is how a forbidden word eventually ships.
module Copy
  module_function

  def headline(scored)
    item = scored.item
    return I18n.t("freshness.check_it", name: bare_name(item)) if item.high_risk? && scored.phase == "at_risk"

    case scored.phase
    when "fresh" then I18n.t("freshness.fine", count: approx(scored.days_left))
    when "aging" then I18n.t("freshness.aging", count: approx(scored.days_left))
    when "at_risk"
      scored.days_left <= 0 ? I18n.t("freshness.today") : I18n.t("freshness.soon", count: scored.days_left)
    else I18n.t("freshness.probably_gone")
    end
  end

  # Rounds to a vagueness the estimate actually supports. Saying "about a week"
  # when we mean 6.4 days is honest; saying "expires Friday" is not.
  def approx(days)
    return 0 if days <= 0
    return days if days <= 3

    (days / 2.0).round * 2
  end

  def bare_name(item) = item.display_name.sub(/\A\p{Emoji_Presentation}\s*/, "")
end
