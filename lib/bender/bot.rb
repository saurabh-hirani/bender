require 'thread'

require 'robut'
require 'robut/storage/yaml_store'
require 'fuzzystringmatch'

require_relative 'main'

Bot = Robut # alias



module Bot
  def self.set var, val
    Bot::Plugin::Bender.class_variable_set "@@#{var}".to_sym, val
  end

  def self.run!
    Bot::Plugin.plugins = [ Bot::Plugin::Bender ]
    Bot::Web.set :connection, Bot::Connection.new.connect
  end
end



module Bot
  module Plugin
    class Bender
      JARROW = FuzzyStringMatch::JaroWinkler.create :native

      include Bot::Plugin


      def handle time, sender, message
        nick = lookup_user(sender)[:nick] rescue return

        case message
        when /whoami/
          reply '%s: %s' % [ nick, sender ]
        end

        return true
      end


    private

      def lookup_user name
        @@users.values.sort_by do |u|
          JARROW.getDistance name, u[:name]
        end.last
      end

    end
  end
end