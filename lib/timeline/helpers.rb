module Timeline
  module Helpers
    class DecodeException < StandardError; end

    def encode(object)
      ::MultiJson.encode(object)
    end

    def decode(object)
      return unless object

      begin
        ::MultiJson.decode(object)
      rescue ::MultiJson::DecodeError => e
        raise DecodeException, e
      end
    end

    def get_list(options={})
      Timeline.redis.lrange options[:list_name], options[:start], options[:end]
    end

    def get_global_activity(start = 0, stop = 19)
      Timeline.redis.lrange("global:activity", start, stop).map do |item|
          ::Timeline::Activity.new ::Timeline.decode(item)
      end
    end
  end
end
