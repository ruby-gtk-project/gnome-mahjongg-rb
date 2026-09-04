# frozen_string_literal: true

module Mahjongg
  # Where the shipped data and the player's save/score files live. Upstream
  # reads its data out of a GResource bundle compiled into the binary; there is
  # no equivalent for a plain Ruby script, so the files stay on disk and the
  # installed wrapper points MAHJONGG_RB_DATA_DIR at them.
  module Paths
    module_function

    def data_dir
      ENV.fetch('MAHJONGG_RB_DATA_DIR', File.expand_path('../../data', __dir__))
    end

    def data_file(relative) = File.join(data_dir, relative)

    def user_data_dir
      File.join(
        ENV.fetch('XDG_DATA_HOME', File.join(Dir.home, '.local', 'share')),
        'gnome-mahjongg-rb',
      )
    end

    def user_data_file(relative) = File.join(user_data_dir, relative)
  end
end
