# frozen_string_literal: true

desc 'Compile the GSettings schema'
task :schema do
  sh 'glib-compile-schemas', 'data/schemas'
end

desc 'Run the test suite (renders offscreen; needs no display)'
task test: :schema do
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

task default: %i[schema test lint]
