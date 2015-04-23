require 'logger'

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


    desc 'start', 'Start Bender Web server and HipChat receiver'
    option :bind, \
      type: :string,
      aliases: %w[ -b ],
      desc: 'Set Sinatra interface',
      default: '0.0.0.0'
    option :port, \
      type: :numeric,
      aliases: %w[ -p ],
      desc: 'Set Sinatra port',
      default: 4567
    option :environment, \
      type: :string,
      aliases: %w[ -e ],
      desc: 'Set Sinatra environment',
      default: 'development'
    include_common_options
    def start
      Bot.run!

      Web.set :environment, options.environment
      Web.set :port, options.port
      Web.set :bind, options.bind
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