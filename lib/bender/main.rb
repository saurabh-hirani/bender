require 'logger'

require 'tilt/erb'

require_relative 'metadata'
require_relative 'mjolnir'
require_relative 'web'
require_relative 'bot'


module Bender
  class Main < Mjolnir

    desc 'version', 'Echo the application version'
    def version
      puts VERSION
    end


    desc 'art', 'View the application art'
    def art
      puts "\n%s\n" % ART
    end



    desc 'bot', 'Start Bender HipChat bot and Web server'
    option :bind, \
      type: :string,
      aliases: %w[ -b ],
      desc: 'Set Sinatra interface',
      default: '0.0.0.0'
    option :port, \
      type: :numeric,
      aliases: %w[ -o ],
      desc: 'Set Sinatra port',
      default: 4567
    option :environment, \
      type: :string,
      aliases: %w[ -e ],
      desc: 'Set Sinatra environment',
      default: 'development'
    option :jid, \
      type: :string,
      aliases: %w[ -j ],
      desc: 'Set HipChat JID',
      required: true
    option :password, \
      type: :string,
      aliases: %w[ -p ],
      desc: 'Set HipChat password',
      required: true
    option :nick, \
      type: :string,
      aliases: %w[ -n ],
      desc: 'Set HipChat nick name',
      required: true
    option :mention, \
      type: :string,
      aliases: %w[ -m ],
      desc: 'Set HipChat mention name',
      required: true
    option :rooms, \
      type: :string,
      aliases: %w[ -r ],
      desc: 'Set HipChat rooms (comma-separated)',
      required: true
    option :database, \
      type: :string,
      aliases: %w[ -d ],
      desc: 'Set path to application database',
      required: true
    include_common_options
    def start
      Bot::Connection.configure do |config|
        config.jid = options.jid
        config.password = options.password
        config.nick = options.mention
        config.mention_name = options.nick
        config.rooms = options.rooms.split(',')

        Bot::Storage::YamlStore.file = options.database
        config.store = Bot::Storage::YamlStore

        config.logger = log
      end

      Bot.run!


      Web.set :environment, options.environment
      Web.set :port, options.port
      Web.set :bind, options.bind
      Web.set :store, options.database

      if log.level >= ::Logger::DEBUG
        Web.set :raise_errors, true
        Web.set :dump_errors, true
        Web.set :show_exceptions, true
        Web.set :logging, ::Logger::DEBUG
      end

      Web.run!
    end


  end
end