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

require 'thread'
require 'socket'
require 'singleton'
require 'getoptlong'
require 'castoro-pgctl/barrier'
require 'castoro-pgctl/component'
require 'castoro-pgctl/signal_handler'
require 'castoro-pgctl/exceptions'
require 'castoro-pgctl/configurations'

module Castoro
  module Peer
    
    PROGRAM_VERSION = "0.0.2 - 2012-05-31"

    class SubCommand
      def initialize
        @options = []
        parse_arguments
      end

      def parse_arguments
        while ( x = ARGV.shift )
          begin
            Socket.gethostbyname x  # determine if the parameter is a hostname
            ARGV.unshift x          # it is a hostname
            break                   # quit here
          rescue SocketError => e
            # intentionally ignored. it is not a hostname
          end
          x.match( /\A[a-zA-Z0-9_ -]*\Z/ ) or raise CommandLineArgumentError, "Non-alphanumeric letter is not allowed in the command line: #{x}"
          @options.push x
        end
      end

      def title message
        puts "[ #{Time.new.to_s}  #{message} ]"
      end

      def xxxxx &block
        @x = Component.get_peer_group
        Barrier.instance.clients = @x.number_of_components + 1
        if block_given?
          yield
        end
        Barrier.instance.wait  # let slaves start
        Barrier.instance.wait  # wait until slaves finish their tasks
        Exceptions.instance.confirm
      end

      def do_start_daemons
        title "Starting daemons"
        xxxxx { @x.do_start }
        @x.print_start
        Exceptions.instance.confirm
      end

      def do_stop_deamons
        title "Stopping daemons"
        xxxxx { @x.do_stop }
        @x.print_stop
        Exceptions.instance.confirm
      end

      def do_ps
        xxxxx { @x.do_ps }
        Exceptions.instance.confirm
      end

      def do_ps_and_print
        title "Daemon processes"
        do_ps
        @x.print_ps
      end

      def do_status
        xxxxx { @x.do_status }
        Exceptions.instance.confirm
      end

      def do_status_and_print
        title "Status"
        do_ps
        do_status
        @x.print_status
      end

      def turn_autopilot_off
        title "Turning the autopilot off"
        xxxxx { @x.do_auto false }
        @x.print_auto
        @x.verify_auto false
        Exceptions.instance.confirm
      end

      def turn_autopilot_on
        title "Turning the autopilot auto"
        xxxxx { @x.do_auto true }
        @x.print_auto
        @x.verify_auto true
        Exceptions.instance.confirm
      end

      def ascend_the_mode_to mode
        m = ServerStatus.status_code_to_s( mode )
        title "Ascending the mode to #{m}"
        xxxxx { @x.ascend_mode mode }
        @x.print_mode
        Exceptions.instance.confirm
      end

      def descend_the_mode_to mode
        m = ServerStatus.status_code_to_s( mode )
        title "Descending the mode to #{m}"
        xxxxx { @x.descend_mode mode }
        @x.print_mode
        Exceptions.instance.confirm
      end

      def descend_the_mode_to_readonly
        turn_autopilot_off     ; sleep 2
        do_status_and_print
        SignalHandler.check    ; sleep 2

        m = @x.mode
         if m.nil? or 30 <= m
          descend_the_mode_to 25 ; sleep 2  # 25 fin_rep
          do_status_and_print
          @x.verify_mode_less_or_equal 25
          SignalHandler.check ; sleep 2
        end

        m = @x.mode
        if m.nil? or 25 <= m
          descend_the_mode_to 23 ; sleep 2  # 23 rep
          do_status_and_print
          @x.verify_mode_less_or_equal 23
          SignalHandler.check ; sleep 2
        end

        m = @x.mode
        if m.nil? or 23 <= m
          descend_the_mode_to 20 ; sleep 2  # 20 readonly
          do_status_and_print
          @x.verify_mode_less_or_equal 20 ; sleep 2
          SignalHandler.check ; sleep 2
        end
      end

      def descend_the_mode_to_offline
        descend_the_mode_to_readonly

        m = @x.mode
        if m.nil? or 20 <= m
          descend_the_mode_to 10 ; sleep 2  # 10 offline
          do_status_and_print
          @x.verify_mode_less_or_equal 10
          SignalHandler.check ; sleep 2
        end
      end
    end


    class PsSubCommand < SubCommand
      def run
        do_ps_and_print
      end
    end


    class StatusSubCommand < SubCommand
      def run
        do_status_and_print
      end
    end


    class StartAllSubCommand < SubCommand
      def run
        do_ps_and_print
        SignalHandler.check

        unless @x.alive?
          do_start_daemons       ; sleep 2
          do_ps_and_print
          @x.verify_start        ; sleep 2
          SignalHandler.check
        end

        do_status_and_print
        unless @x.mode == 30
          turn_autopilot_off     ; sleep 2
          do_status_and_print    ; sleep 2
          SignalHandler.check

          ascend_the_mode_to 30  ; sleep 2
          do_status_and_print
          @x.verify_mode_more_or_equal 30 ; sleep 2
          SignalHandler.check

          turn_autopilot_on      ; sleep 2
        end

        do_ps_and_print
        do_status_and_print
        @x.verify_mode 30
        sleep 2

        do_status_and_print
        @x.verify_mode 30
      end
    end


    class StartSubCommand < SubCommand
      def run
        do_ps_and_print
        SignalHandler.check

        @y = Component.get_the_first_peer
        unless @y.alive?
          title "Starting the daemon"
          Barrier.instance.clients = @y.number_of_components + 1
          @y.do_start
          Barrier.instance.wait  # let slaves start
          Barrier.instance.wait  # wait until slaves finish their tasks
          @y.print_start
          Exceptions.instance.confirm
          sleep 2
          do_ps_and_print
          @y.verify_start
          SignalHandler.check
        end

        @x = Component.get_peer_group
        do_status_and_print    ; sleep 2
        SignalHandler.check

        unless @x.mode == 30
          turn_autopilot_off     ; sleep 2
          do_status_and_print    ; sleep 2
          SignalHandler.check

          ascend_the_mode_to 30  ; sleep 2
          do_status_and_print
          SignalHandler.check

          @x.verify_mode_more_or_equal 30 ; sleep 2
          turn_autopilot_on      ; sleep 2
        end

        do_ps_and_print
        do_status_and_print
        @x.verify_mode 30
        sleep 2

        do_status_and_print
        @x.verify_mode 30
      end
    end


    class StopSubCommand < SubCommand
      def run
        do_ps_and_print
        do_status_and_print
        SignalHandler.check

        @y = Component.get_the_first_peer
        if false == @y.alive?
          puts "The deamons on the peer have already stopped."
          return
        end

        descend_the_mode_to_readonly

        mode = 10
        m = ServerStatus.status_code_to_s( mode )
        title "Descending the mode to #{m}"
        @y = Component.get_the_first_peer
        Barrier.instance.clients = @y.number_of_components + 1
        @y.descend_mode 10  # 10 offline
        Barrier.instance.wait  # let slaves start
        Barrier.instance.wait  # wait until slaves finish their tasks
        @y.print_mode
        Exceptions.instance.confirm

        do_status_and_print
        @y.verify_mode_less_or_equal 10
        SignalHandler.check
        sleep 2

        title "Stopping the daemon"
        @y = Component.get_the_first_peer
        Barrier.instance.clients = @y.number_of_components + 1
        @y.do_stop
        Barrier.instance.wait  # let slaves start
        Barrier.instance.wait  # wait until slaves finish their tasks
        @y.print_stop
        Exceptions.instance.confirm
        sleep 2

        do_ps_and_print
        SignalHandler.check

        @z = Component.get_the_rest_of_peers
        Barrier.instance.clients = @z.number_of_components + 1
        if 0 < @z.number_of_components
          title "Turning the autopilot auto"
          @z.do_auto true
          Barrier.instance.wait  # let slaves start
          Barrier.instance.wait  # wait until slaves finish their tasks
          @z.print_auto
          @z.verify_auto true
          Exceptions.instance.confirm
          sleep 2

          do_ps_and_print
          SignalHandler.check
        end

        do_status_and_print
        @y.verify_stop
        @z.verify_alive
        @z.verify_mode 20
      end
    end

    class StopAllSubCommand < SubCommand
      def run
        do_ps_and_print
        do_status_and_print
        SignalHandler.check

        if false == @x.alive?
          puts "All deamons on every peer have already stopped."
          return
        end

        descend_the_mode_to_offline
        do_stop_deamons
        SignalHandler.check
        sleep 2

        do_ps_and_print
        do_status_and_print
        @x.verify_stop
      end
    end


    class PgctlMain
      include Singleton

      def initialize
        @program_name = $0.sub( %r{.*/}, '' )  # name of this command
      end

      def parse_command_line_options
        x = GetoptLong.new(
              [ '--help',                '-h', GetoptLong::NO_ARGUMENT ],
              [ '--debug',               '-d', GetoptLong::NO_ARGUMENT ],
              [ '--version',             '-V', GetoptLong::NO_ARGUMENT ],
              [ '--configuration-file',  '-c', GetoptLong::REQUIRED_ARGUMENT ],
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
            Configurations.file = arg
          end
        end
      end

      def parse_sub_command
        x = ARGV.shift
        x.nil? and raise CommandLineArgumentError, "No sub-command is given."
        case x
        when 'ps'       ; PsSubCommand.new
        when 'status'   ; StatusSubCommand.new
        when 'startall' ; StartAllSubCommand.new
        when 'stopall'  ; StopAllSubCommand.new
        when 'start'    ; StartSubCommand.new
        when 'stop'     ; StopSubCommand.new
        else
          raise CommandLineArgumentError, "Unknown sub-command: #{x}"
        end
      end

      def parse_hostnames
        Array.new.tap do |a|  # array of hostnames
          ARGV.each do |x|    # argument
            begin
              Socket.gethostbyname x  # confirm if the argument can be resolved as a hostname.
              a.push x  # hostname
            rescue SocketError => e
              if e.message.match( /node name .* known/ )  # getaddrinfo: node name or service name not known
                raise CommandLineArgumentError, "Unknown hostname: #{x}"
              else
                raise e
              end
            end
          end
        end
      end

      def usage
        x = @program_name
        puts "usage: #{x} [global options...] sub-command [options...] [parameters...] [hostnames..]"
        puts ""
        puts "  global options:"
        puts "   -h, --help     prints this help message and exit."
        puts "   -d, --debug    this command runs with debug messages being printed."
        puts "   -V, --version  shows a version number of this command."
        puts "   -c file, --configuration-file=file  specifies a configuration file."
        puts "                  default: /etc/castoro/pgctl.conf"
        puts ""
        puts "  sub commands:"
        puts "   ps         lists the deamon processes in a 'ps -ef' format"
        puts "   status     shows the status of the deamon processes on the every host"
        puts "   startall   starts deamon processes on every host of the peer group"
        puts "   stopall    stops  daemon processes on every host of the peer group"
        puts "   start      starts daemon processes on the only target peer host"
        puts "   stop       stops  daemon processes on the only target peer host"
        puts ""
        puts " examples:"
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
        puts "   #{x} stopall peer01 peer02 peer03"
        puts "        peer01 peer02, and peer03 will be stopped."
        puts ""
        puts "   #{x} startall peer01 peer02 peer03"
        puts "        peer01 peer02, and peer03 will be started, then be online."
        puts ""
      end

      def parse
        parse_command_line_options
        command = parse_sub_command
        hostnames = parse_hostnames
        hostnames.each do |h|  # hostname
          Component.add_peer h
        end
        command
      rescue CommandLineArgumentError => e
        STDERR.puts "#{@program_name}: #{e.message}"
        puts ""
        usage
        Process.exit 1
      end

      def run
        args = ARGV.join(' ')
        command = parse
        SignalHandler.setup
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
