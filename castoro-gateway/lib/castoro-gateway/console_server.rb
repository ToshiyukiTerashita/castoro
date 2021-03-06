#
#   Copyright 2010 Ricoh Company, Ltd.
#
#   This file is part of Castoro.
#
#   Castoro is free software: you can redistribute it and/or modify
#   it under the terms of the GNU Lesser General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   Castoro is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU Lesser General Public License for more details.
#
#   You should have received a copy of the GNU Lesser General Public License
#   along with Castoro.  If not, see <http://www.gnu.org/licenses/>.
#

require "castoro-gateway"

require "logger"
require "monitor"
require "drb/drb"
require "stringio"

module Castoro
  class Gateway
    #
    # This class is basic class of IslandConsoleServer and MasterConsoleServer.
    #
    class ConsoleServer

      DEFAULT_OPTIONS = {
        #:host => "127.0.0.1",
        :gets_expire => 5.0,
        :fork => true,
      }

      @@forker = Proc.new { |pin, pout, &block|
        pid = fork {
          begin
            pin.close
            block.call
          rescue
            pout.puts
          end
        }
        pout.close
        pid
      }

      @@noforker = Proc.new { |pin, pout, &block|
        begin
          block.call
        rescue
          pout.puts
        end
        nil
      }

      #
      # --arg
      #  logger     Specify logger instance 
      #  repository When type is island or original, specify Repository class instance
      #             When type is master,  specify IslandStatus class instance
      #  ip         IP Address String
      #  port       Port number
      def initialize logger, repository, ip, port, options = {}
        @logger = logger
        @repository = repository

        @options = DEFAULT_OPTIONS.merge(options || {})
        @uri = "druby://#{ip}:#{port}"
        @locker = Monitor.new
      end

      def start
        @locker.synchronize {
          raise CastoroError, "console server already started." if alive?
          @server = DRb::DRbServer.new @uri, self
          @logger.info { "console server DRbService start #{@uri}"}
        }
      end

      def stop
        @locker.synchronize {
          raise CastoroError, "console server already stopped." unless alive?
          @server.stop_service
          @server = nil
          @logger.info { "console server DRbService stop #{@uri}"}
       }
      end

      def alive?
        @locker.synchronize {
          !! (@server and @server.alive?)
        }
      end
    end  

    ##
    # MasterConsoleServer
    #
    # This console server is used when gateway's type is master.
    #
    class MasterConsoleServer < ConsoleServer
      def initilaize  logger, repository, ip, port, options = {}
        super logger, repository, ip, port, options
      end

      def status 
        @repository.status 
  
        #result = []
        #st = @repository.status         
        #st.each do |key, value|
        #   result.push [ key, value[:storables], value[:capacity] ]
        #end
        #result
      end
    end

    ##
    # IslandConsoleServer
    #
    # This console server is used when gateway's type is island or original.
    #
    class IslandConsoleServer < ConsoleServer
      def initilaize  logger, repository, ip, port, options = {}
        super logger, repository, ip, port, options
      end  

      def status
        @repository.status
      end

      def peers_status
        @repository.peers_status
      end

      def dump io
        dump_internal io
      end

      def purge *peers
        io = StringIO.new
        dump_internal io, peers
        results = {}.tap { |r| peers.each { |p| r[p] = 0 } }
        io.string.split(/\n/).each { |line|
          p, b = line.split(":", 2).map(&:strip)
          if b and p
            results[p] += 1
            @repository.drop b, p
          end
        }
        results
      end

      private

      def dump_internal io, peers = nil
        pin, pout = IO.pipe
        pid = forker.call(pin, pout) { @repository.dump pout, peers }

        while (line = gets_with_timeout(pin))
          io.puts line
        end
        io.puts

      ensure
        Process.detach pid if pid
      end

      def gets_with_timeout io
        if IO.select([io], nil, nil, @options[:gets_expire]) and (line = io.gets)
          line.chomp.tap { |l|
            return nil if l.strip.empty?
          }
        end
      end

      def forker
        @options[:fork] ? @@forker : @@noforker
      end
    end
  end
end

