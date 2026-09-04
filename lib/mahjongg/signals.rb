# frozen_string_literal: true

module Mahjongg
  # Upstream's model objects are GObjects and talk to the UI through GObject
  # signals. Registering Ruby GTypes just to get multicast callbacks would buy
  # nothing here, so the same shape is done with plain blocks.
  module Signals
    def on(name, &block)
      handlers[name] << block
      block
    end

    def emit(name, *args)
      handlers[name].map { |handler| handler.call(*args) }
    end

    def handlers
      @handlers ||= Hash.new { |hash, key| hash[key] = [] }
    end
  end
end
