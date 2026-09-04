# frozen_string_literal: true

require 'gettext'

require_relative 'paths'

module Mahjongg
  # Translations, from upstream's own message catalogues. Because they are
  # reused unchanged, every string in this port has to match its msgid
  # exactly — including the msgctxt disambiguators that keep, say, the "Light"
  # background apart from any other "Light".
  #
  # Include this in a class to get `_` and `p_`.
  module I18n
    include GetText

    DOMAIN = 'gnome-mahjongg-rb'

    # GTK and Pango want UTF-8 whatever the locale's own charset is. Without
    # this the gettext gem transcodes to the locale charset, and every umlaut
    # in a German run comes out as "?".
    bindtextdomain(DOMAIN, path: Paths.locale_dir, output_charset: 'UTF-8')
  end
end
