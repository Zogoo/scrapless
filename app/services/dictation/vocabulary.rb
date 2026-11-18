module Dictation
  # How each of the app's languages is spoken at the mic, read from
  # config/dictation/<locale>.yml for every locale in
  # config.i18n.available_locales.
  #
  # The segmenter uses all languages at once, because a Berlin list is often
  # mixed; the transcriber uses the one the person chose. Adding a phrase or a
  # language is a data change: no list of words lives in code.
  class Vocabulary
    KEYS = %w[transcription_prompt separators leading trailing modifiers numbers units].freeze

    Language = Struct.new(:locale, :transcription_prompt, :separators, :leading, :trailing,
                          :modifiers, :numbers, :units, keyword_init: true)

    class << self
      def locales = I18n.available_locales.map(&:to_s)

      def supported?(locale) = locales.include?(locale.to_s)

      def for(locale)
        languages.fetch(locale.to_s) { raise KeyError, "no dictation data for #{locale}" }
      end

      # Every language's phrases together, normalised the way the dictionary is.
      def combined
        @combined ||= begin
          all = languages.values
          {
            separators: all.flat_map(&:separators).to_set,
            leading: all.flat_map(&:leading).to_set,
            trailing: all.flat_map(&:trailing).to_set,
            modifiers: all.flat_map(&:modifiers).to_set,
            units: all.flat_map(&:units).to_set,
            numbers: all.map(&:numbers).reduce({}, :merge)
          }.freeze
        end
      end

      def reset! = (@languages = @combined = nil)

      private

      def languages
        @languages ||= locales.index_with { |locale| load(locale) }
      end

      def load(locale)
        data = YAML.safe_load_file(Rails.root.join("config/dictation/#{locale}.yml"))
        missing = KEYS - data.keys
        raise KeyError, "config/dictation/#{locale}.yml is missing #{missing.join(', ')}" if missing.any?

        Language.new(
          locale: locale,
          transcription_prompt: data["transcription_prompt"],
          separators: keys(data["separators"]),
          leading: keys(data["leading"]),
          trailing: keys(data["trailing"]),
          modifiers: keys(data["modifiers"]),
          units: keys(data["units"]),
          numbers: data["numbers"].to_h { |word, value| [ ProductAlias.normalize_key(word), Integer(value) ] }
        )
      end

      def keys(list) = Array(list).map { |p| ProductAlias.normalize_key(p.to_s) }.reject(&:blank?)
    end
  end
end
