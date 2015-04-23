require 'pathname'
require 'thread'
require 'json'

require 'sinatra/base'

require_relative 'metadata'

Thread.abort_on_exception = true


module Bender
  class Web < Sinatra::Application
    set :root, File.join(Bender::ROOT, 'web')

    get '/v' do
      content_type :text
      VERSION
    end

    get '/' do
      erb :app
    end

    get '/favicon.ico' do
      send_file File.join(settings.root, 'favicon.ico'), \
        disposition: 'inline'
    end

    get %r|/app/(.*)| do |fn|
      send_file File.join(settings.root, 'app', fn), \
        disposition: 'inline'
    end

  end
end