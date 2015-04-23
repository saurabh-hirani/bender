require 'thread'



module Bender
  class Bot
    @@singleton = nil

    def self.run!
      @@singleton ||= Bot.new
    end


    def initialize
      Thread.new do
        loop do
          puts 'Running Bot...'
          sleep 5
        end
      end
    end

  end
end