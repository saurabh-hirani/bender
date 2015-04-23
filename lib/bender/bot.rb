require 'thread'

require 'robut'
require 'robut/storage/yaml_store'

Bot = Robut # alias



module Bot
  def self.run!
    Bot::Plugin.plugins = [ Bot::Plugin::Bender ]
    Bot::Web.set :connection, Bot::Connection.new.connect
  end
end


module Bot
  module Plugin
    class Bender
      include Bot::Plugin


      def handle time, sender, message
        if message =~ /bender/
          reply 'What, %s?! (%s)' % [ sender, time ]
        end

        return true
      end

    end
  end
end