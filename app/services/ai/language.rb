module Ai
  # The language every model answer is written in: the one the person's app is
  # set to (I18n.locale, from the X-Locale header).
  #
  # Each locale file names its own language in English for the prompt
  # (`language.english_name`), so adding a language is adding a locale file,
  # not editing a list here.
  module Language
    module_function

    def name(locale = I18n.locale)
      I18n.t("language.english_name", locale: locale,
                                      default: I18n.t("language.english_name", locale: I18n.default_locale))
    end
  end
end
