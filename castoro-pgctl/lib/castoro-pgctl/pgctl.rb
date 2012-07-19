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

if $0 == __FILE__
  $LOAD_PATH.dup.each do |x|
    $LOAD_PATH.delete x if x.match %r(/gems/)
  end
  $LOAD_PATH.unshift '..'
end

require 'singleton'
require 'getoptlong'
require 'castoro-pgctl/component'
require 'castoro-pgctl/signal_handler'
require 'castoro-pgctl/exceptions'
require 'castoro-pgctl/configurations_pgctl'
require 'castoro-pgctl/configurations_peer'
require 'castoro-pgctl/sub_command'

module Castoro
  module Peer
    
    PROGRAM_VERSION = "0.0.2 - 2012-05-31"

    class PgctlMain
      include Singleton

      def initialize
        @program_name = $0.sub( %r{.*/}, '' )  # name of this command
      end

      def usage
        x = @program_name
        puts "usage: #{x} [global options...] sub-command [options...] [parameters...] [hostnames..]"
        puts ""
        puts "  global options:"
        puts "   -h, --help     prints this help message and exit."
        puts "   -d, --debug    this command runs with debug messages being printed."
        puts "   -V, --version  shows a version number of this command."
        puts "   -c file, --configuration-file=file  specifies a configuration file of pgctl."
        puts "                  default: #{Configurations::Pgctl::DEFAULT_FILE}"
        puts "   -p file, --peer-configuration-file=file  specifies a configuration file of peer."
        puts "                  default: #{Configurations::Peer::DEFAULT_FILE}"
        puts ""
        puts "  sub commands:"
        puts "   list       lists peer groups"
        puts "   ps         lists the deamon processes in a 'ps -ef' format"
        puts "   status     shows the status of the deamon processes on the every host"
        puts "   gstart     starts deamon processes of every host in the peer group"
        puts "   gstop      stops  daemon processes of every host in the peer group"
        puts "   start      starts daemon processes of the only target peer host"
        puts "   stop       stops  daemon processes of the only target peer host"
        puts "   kill       stops  daemon processes of the specified peer host by force without any check"
        puts ""
        puts " examples:"
        puts "   #{x} list"
        puts "        shows a list of peer groups"
        puts ""
        puts "   #{x} status peer01 peer02 peer03"
        puts "        shows the status of peer01, peer02, and peer03."
        puts ""
        puts "   #{x} stop peer01 peer02 peer03"
        puts "        peer01 will be stopped."
        puts "        peer02 and peer03 will be readonly."
        puts ""
        puts "   #{x} start peer01 peer02 peer03"
        puts "        peer01 will be started, then"
        puts "        peer01, peer02, and peer03 will be online."
        puts ""
        puts "   #{x} gstop G00"
        puts "        peer01 peer02, and peer03 will be stopped."
        puts ""
        puts "   #{x} gstart G00"
        puts "        peer01 peer02, and peer03 will be started, then be online."
        puts ""
      end

      def parse_options
        x = GetoptLong.new(
              [ '--help',                '-h', GetoptLong::NO_ARGUMENT ],
              [ '--debug',               '-d', GetoptLong::NO_ARGUMENT ],
              [ '--version',             '-V', GetoptLong::NO_ARGUMENT ],
              [ '--configuration-file',  '-c', GetoptLong::REQUIRED_ARGUMENT ],
              [ '--peer-configuration-file',  '-p', GetoptLong::REQUIRED_ARGUMENT ],
              )

        x.each do |opt, arg|
          case opt
          when '--help'
            usage
            Process.exit 0
          when '--debug'
            $DEBUG = true
          when '--version'
            puts "#{@program_name} - Version #{PROGRAM_VERSION}"
            Process.exit 0
          when '--configuration-file'
            Configurations::Pgctl.file = arg
          when '--peer-configuration-file'
            Configurations::Peer.file = arg
          end
        end
      end

      def parse_sub_command
        x = ARGV.shift
        x.nil? and raise CommandLineArgumentError, "No sub-command is given."
        case x
        when 'list'     ; SubCommand::List.new
        when 'ps'       ; SubCommand::Ps.new
        when 'status'   ; SubCommand::Status.new
        when 'gstart'   ; SubCommand::Gstart.new
        when 'gstop'    ; SubCommand::Gstop.new
        when 'start'    ; SubCommand::Start.new
        when 'stop'     ; SubCommand::Stop.new
        when 'kill'     ; SubCommand::Kill.new
        else
          raise CommandLineArgumentError, "Unknown sub-command: #{x}"
        end
      end

      def parse
        parse_options
        parse_sub_command
      rescue CommandLineArgumentError => e
        STDERR.puts "#{@program_name}: #{e.message}"
        puts ""
        puts "Use \"#{@program_name} -h\" to see the help messages"
        Process.exit 1
      end

      def run
        args = ARGV.join(' ')
        command = parse
        SignalHandler.setup

        # Singleton seems not multithread-safe
        Configurations::Pgctl.instance
        Configurations::Peer.instance

        command.run
        SignalHandler.final_check
        puts "\nSucceeded:\n #{@program_name} #{args}"
      rescue Failure::Base => e
        puts "\nOne or more errors occurred:"
        m = e.message.gsub( %r/\n/, "\n " )
        puts " #{m}"
        puts "\nFailed:\n #{@program_name} #{args}"
        Process.exit 2
      end
    end

  end
end

if $0 == __FILE__
  Castoro::Peer::PgctlMain.instance.run
end
