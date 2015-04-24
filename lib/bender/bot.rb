require 'thread'

require 'robut'
require 'robut/storage/yaml_store'
require 'fuzzystringmatch'

Bot = Robut # alias



module Bot
  def self.run!
    Bot::Plugin.plugins = [ Bot::Plugin::Bender ]
    conn = Bot::Connection.new
    conn.store['users'] ||= {}
    Bot::Web.set :connection, conn.connect
    return conn
  end
end



module Bot
  module Plugin
    class Bender
      include Bot::Plugin

      JARO = FuzzyStringMatch::JaroWinkler.create :native



      def handle time, sender, message
        case message

        when /^\s*!whoami\s*$/
          u = user_where name: sender
          reply '%s: %s (%s)' % [ u[:nick], u[:name], u[:email] ]

        when /^\s*!lookup\s+(.+)\s*$/
          u = user_where(name: $1) || user_where(nick: $1)
          reply '%s: %s (%s)' % [ u[:nick], u[:name], u[:email] ]

        end

        return true
      end



    private

      def user_where fields, threshold=0.8
        field, value = fields.to_a.shift
        suggested_user = store['users'].values.sort_by do |u|
          compare value, u[field]
        end.last

        distance = compare value, suggested_user[field]
        return distance < threshold ? nil : suggested_user
      end


      def compare name1, name2
        n1 = name1.gsub /\W/, ''
        n2 = name2.gsub /\W/, ''
        d1 = JARO.getDistance n1.downcase, n2.downcase
        d2 = JARO.getDistance n1, n2
        return d1 + d2 / 2.0
      end

    end
  end
end