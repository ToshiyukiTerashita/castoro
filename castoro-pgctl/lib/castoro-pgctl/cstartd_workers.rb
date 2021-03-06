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

require 'castoro-pgctl/worker'
require 'castoro-pgctl/tcp_socket'
require 'castoro-pgctl/channel'
require 'castoro-pgctl/process_executor'
require 'castoro-pgctl/configurations_pgctl'
require 'castoro-pgctl/log'
require 'castoro-pgctl/exceptions'

module Castoro
  module Peer

    class CstartdWorkers
      def initialize
        @server = CstartdTcpServer.new
      end

      def start
        @server.start
      end

      def stop
        @server.stop
      end
    end


    class CstartdTcpServer < Worker
      def initialize
        port = Configurations::Pgctl.instance.cstartd_comm_tcpport
        addr = '0.0.0.0'
        backlog = 5
        @server = TcpServer.new addr, port, backlog
        super
      end

      def serve
        begin
          connected_socket = @server.accept
        rescue IOError, Errno::EBADF => e
          # IOError "closed stream"
          # Errno::EBADF "Bad file number"
          if @stop_requested
            @finished = true
            return
          else
            raise e
          end
        end

        # Workaround for http://redmine.ruby-lang.org/issues/show/2371
        Log.stop
        pid = Process.fork  # fork returns a Fixnum
        Log.start_again

        if pid
          # Parent process
          connected_socket.close
          Thread.new( pid ) do |x|  # x should be assigned with a value of pid through by-value rather than by-reference
            x_pid, x_status = Process.waitpid2 x
            Log.debug "Child process #{x_pid} exited with #{x_status.exitstatus}" if $DEBUG

            # something goes wrong with Ruby 1.9.2 running on CentOS 6.2
            # so, do it in another thread
            Thread.new do
              CstartdMain.instance.shutdown_requested if x_status.exitstatus == 99
            end
          end
        else
          # Child process
          status = 1
          begin
            @server.close
            cp = CommandProcessor.new connected_socket
            status = cp.process
            connected_socket.close unless connected_socket.closed?
            sleep 0.5
          rescue => e
            Log.warning e
            Log.stop  # think if this is OK. It is called in the rescue cause.
            Process.exit! 1
          end
          Log.stop
          Process.exit! status
        end
      end

      def stop
        @stop_requested = true
        @server.close if @server
        super
      end
    end


    class DealingWithPidFileOfManipulatord
      # This path is defined in ../../../castoro-manipulator/bin/castoro-manipulator
      PID_FILE = "/var/castoro/manipulator.pid"

      def initialize
        @file = PID_FILE
      end

      def prepare_for_start
        File.exist?( @file ) or return

        pid = File.open( @file ) do |f|
          x = f.gets
          m = x.match( /([0-9]+)/ ) or return
          m[1]
        end

        if File.exist? "/proc/#{pid}"
          raise ManipulatorPidFileError, "A process id file of castoro-manipulator exists and a corresponding process is running: #{@file} #{pid}"
        else
          File.unlink @file
        end
      end
    end


    class CommandProcessor
      def initialize socket
        @socket = socket
      end

      def process
        channel = TcpServerChannel.new @socket
        loop do
          command, args = channel.receive_command
          command.nil? and return 0  # end of file reached

          case command
          when 'QUIT'     ; return 0
          when 'SHUTDOWN' ; return 99
          end

          begin
            target = args[ 'target' ] or raise ArgumentError, "target is not specified"
            result = case command
                     when 'START'    ; do_initd target, 'start'
                     when 'STOP'     ; do_initd target, 'stop'
                     when 'PS'       ; do_ps target
                     else
                       raise BadRequestError, "Unknown command: #{command}"
                     end

          rescue => e
            result = { :error => { :code => e.class, :message => e.message, :backtrace => e.backtrace.slice(0,5) } }

          ensure
            Log.debug "result=#{result.inspect}" if $DEBUG
            channel.send_response result
          end
        end

      rescue => e
        channel.send_response e
        1
      end

      def run *command
        x = ProcessExecutor.new
        x.execute *command
        stdout, stderr = x.gets
        status = x.wait
        [ status, stdout, stderr ]
      end

      def do_initd target, options
        command = {
          'cmond'         => '/etc/init.d/cmond',
          'cpeerd'        => '/etc/init.d/cpeerd',
          'crepd'         => '/etc/init.d/crepd',
          'manipulatord'  => '/etc/init.d/castoro-manipulatord',
        }[ target ] or raise ArgumentError, "Unknown target: #{target}"

        if target == 'manipulatord' and options == 'start'
          DealingWithPidFileOfManipulatord.new.prepare_for_start
        end

        status, stdout, stderr = run command, options
        { :target => target, :status => status, :stdout => stdout, :stderr => stderr }
      end

      def do_ps target
        pattern = {
          'cmond'         => 'bin/cmond',
          'cpeerd'        => 'bin/cpeerd',
          'crepd'         => 'bin/crepd',
          'manipulatord'  => 'bin/castoro-manipulator',
        }[ target ] or raise ArgumentError, "Unknown target: #{target}"

        command = Configurations::Pgctl.instance.cstartd_ps_command
        options = Configurations::Pgctl.instance.cstartd_ps_options.split( ' ' )

        status, stdout, stderr = run( [ command, options ].flatten.join( ' ' ) )
        header = stdout.shift
        stdout = stdout.select { |x| x.match pattern }
        { :target => target, :status => status, :stdout => stdout, :stderr => stderr, :header => header }
      end
    end

  end
end
