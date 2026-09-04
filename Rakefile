# frozen_string_literal: true

desc 'Compile the GSettings schema'
task :schema do
  sh 'glib-compile-schemas', 'data/schemas'
end

desc 'Compile po/*.po into data/locale for gettext'
task :locale do
  require 'fileutils'
  require 'gettext/tools'

  # rmsgfmt rather than GNU msgfmt: for some catalogues msgfmt emits MO format
  # revision 1.1, which the gettext gem's reader rejects outright. The gem's
  # own compiler always writes revision 0.
  languages.each do |language|
    "data/locale/#{language}/LC_MESSAGES".tap do |dir|
      FileUtils.mkdir_p(dir)
      GetText::Tools::MsgFmt.run("po/#{language}.po", '-o', "#{dir}/gnome-mahjongg-rb.mo")
    end
  end
end

def languages
  File.readlines('po/LINGUAS')
      .map(&:strip)
      .reject { |line| line.empty? || line.start_with?('#') }
      .select { |language| File.exist?("po/#{language}.po") }
end

desc 'Regenerate po/gnome-mahjongg-rb.pot from the sources in po/POTFILES.in'
task :pot do
  require 'gettext/tools'

  # The gettext gem's xgettext, because GNU xgettext cannot read Ruby.
  GetText::Tools::XGetText.run(
    '-o',
    'po/gnome-mahjongg-rb.pot',
    *File.readlines('po/POTFILES.in')
         .map(&:strip)
         .reject { |line| line.empty? || line.start_with?('#') }
         .grep(/\.rb\z/),
  )
end

desc 'Merge translations into the desktop entry and the AppStream metainfo'
task :metadata do
  # GNU msgfmt, not the gettext gem: only msgfmt knows the .desktop and
  # AppStream merge formats.
  sh 'msgfmt',
    '--desktop',
    '-d',
    'po',
    '--template=data/org.gnome.Mahjongg.Rb.desktop.in',
    '-o',
    'data/org.gnome.Mahjongg.Rb.desktop'
  sh 'msgfmt',
    '--xml',
    '-d',
    'po',
    '--template=data/org.gnome.Mahjongg.Rb.metainfo.xml.in',
    '-o',
    'data/org.gnome.Mahjongg.Rb.metainfo.xml'
end

desc 'Run the test suite (renders offscreen; needs no display)'
task test: %i[schema locale] do
  %w[test/logic_test.rb test/ui_test.rb].each do |script|
    puts "\n== #{script}"
    sh(
      { 'GSETTINGS_SCHEMA_DIR' => File.expand_path('data/schemas', __dir__) },
      'env',
      '-u',
      'DISPLAY',
      '-u',
      'WAYLAND_DISPLAY',
      'ruby',
      script,
    )
  end
end

desc 'Lint'
task :lint do
  sh 'rubocop'
end

task default: %i[schema locale metadata test lint]
