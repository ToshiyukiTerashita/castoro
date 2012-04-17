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

require 'thread'
require 'socket'
require 'castoro-groupctl/channel'
require 'castoro-groupctl/barrier'
require 'castoro-groupctl/configurations'

module Castoro
  module Peer

    class XBarrier < MasterSlaveBarrierSingleton
    end

    class Proxy
      def initialize hostname, target
        @hostname, @target  = hostname, target
      end
      
      def xxx port, command, args, &block
        Thread.new do
          c = command.dup 
          a = args.dup
          yyy port, c, a, &block
        end
      end

      def yyy port, command, args, &block
        # p [ command, args ]
        XBarrier.instance.wait nil
        socket = TCPSocket.new @hostname, port
        socket.setsockopt Socket::IPPROTO_TCP, Socket::TCP_NODELAY, true
        channel = TcpClientChannel.new socket
        channel.send_command command, args
        x_command, response = channel.receive_response
        socket.close
        # p [ @hostname, @target, command, args, response ]
        if block_given?
          result = yield @hostname, @target, response
        else
          result = [ @hostname, @target, command, args, response ]
        end
        XBarrier.instance.wait result
        response
      rescue => e
        # p e
        XBarrier.instance.wait e
        e
      end

      def ps
        port = Configurations.instance.cstartd_comm_tcpport
        xxx( port, 'PS', { :target => @target } ) do |h, t, r|  # hostname, target, response
          if r.nil?
            Failure.new h, t, nil
          elsif r[ 'error' ]
            e = r[ 'error' ]
            Failure.new h, t, "#{e['code']} #{e['message']} #{e['backtrace'].join(' ')}"
          elsif r[ 'stdout' ]
            Success.new h, t, r[ 'stdout' ]
          else
            Failure.new h, t, "Unknown error: #{r.inspect}"
          end
        end
      end

      def start
        xxx( 'START', { :target => @target } ) do |h, t, r|  # hostname, target, response
          if r.nil?
            Failure.new h, t, nil
          elsif r[ 'error' ]
            e = r[ 'error' ]
            Failure.new h, t, "#{e['code']} #{e['message']} #{e['backtrace'].join(' ')}"
          elsif r[ 'status' ] and r[ 'status' ] != 0
            Failure.new h, t, "status=#{r['status']} #{r['message']}"
          elsif r[ 'status' ] == 0
            if r[ 'stdout' ].find { |x| x.match( /Starting.*NG/ ) } and r[ 'stderr' ].find { |x| x.match( /Errno::EADDRINUSE/ ) }
              Success.new h, t, "Already started"
            else
              Success.new h, t, "status=#{r['status']} #{r['message']}"
            end
          else
            Failure.new h, t, "Unknown error: #{r.inspect}"
          end
        end
      end

      def stop
        port = Configurations.instance.cstartd_comm_tcpport
        xxx( port, 'STOP', { :target => @target } ) do |h, t, r|  # hostname, target, response
          if r.nil?
            Failure.new h, t, nil
          elsif r[ 'error' ]
            e = r[ 'error' ]
            Failure.new h, t, "#{e['code']} #{e['message']} #{e['backtrace'].join(' ')}"
          elsif r[ 'status' ] and r[ 'status' ] != 0
            if t == :manipulatord and r[ 'status' ] == 1 and r[ 'stderr' ].find { |x| x.match( /PID file not found/ ) }
              Success.new h, t, "Already stopped"
            else
              Failure.new h, t, "status=#{r['status']} #{r['message']}"
            end
          elsif r[ 'stdout' ] and r[ 'stdout' ].find { |x| x.match( /Errno::ECONNREFUSED/ ) }
            Success.new h, t, "Already stopped"
          elsif r[ 'status' ] == 0
            Success.new h, t, "status=#{r['status']} #{r['message']}"
          else
            Failure.new h, t, "Unknown error: #{r.inspect}"
          end
        end
      end

      def shutdown
        port = Configurations.instance.cstartd_comm_tcpport
        xxx( port, 'SHUTDOWN', nil )
      end

      def status
        port = Configurations.instance.cagentd_comm_tcpport
        xxx( port, 'STATUS', { :target => @target } ) do |h, t, r|  # hostname, target, response
          if r.nil?
            Failure.new h, t, nil
          elsif r[ 'error' ]
            e = r[ 'error' ]
            Failure.new h, t, "#{e['code']} #{e['message']} #{e['backtrace'].join(' ')}"
          elsif r[ 'mode' ]
            Success.new h, t, r
          else
            Failure.new h, t, "Unknown error: #{r.inspect}"
          end
        end
      end

    end

    class ResultStatus
      attr_reader :hostname, :target, :message

      def initialize hostname, target, message
        @hostname, @target, @message = hostname, target, message
      end
    end

    class Success < ResultStatus
    end

    class Failure < ResultStatus
      attr_reader :backtrace

      def initialize hostname, target, message, backtrace = nil
        super hostname, target, message
        @backtrace = backtrace
      end
    end

    class ManipulatordProxy < Proxy
      def initialize hostname
        super hostname, :manipulatord
      end
    end


    class CxxxdProxy < Proxy

    end


    class CmondProxy < CxxxdProxy
      def initialize hostname
        super hostname, :cmond
      end
    end


    class CpeerdProxy < CxxxdProxy
      def initialize hostname
        super hostname, :cpeerd
      end
    end


    class CrepdProxy < CxxxdProxy
      def initialize hostname
        super hostname, :crepd
      end
    end


    class PeerComponent
      def initialize hostname
        @hostname = hostname
        @leaves = []
        @leaves << CmondProxy.new( @hostname )
        @leaves << CpeerdProxy.new( @hostname )
        @leaves << CrepdProxy.new( @hostname )
        @leaves << ManipulatordProxy.new( @hostname )
      end

      def size
        @leaves.size
      end

      def ps
        @leaves.each do |leaf|
          leaf.ps
        end
      end

      def start
        @leaves.each do |leaf|
          leaf.start
        end
      end

      def stop
        @leaves.each do |leaf|
          leaf.stop
        end
      end
    end


    class CxxxdComponent
      def initialize hostname
        @hostname = hostname
        @leaves = []
        @leaves << CmondProxy.new( @hostname )
        @leaves << CpeerdProxy.new( @hostname )
        @leaves << CrepdProxy.new( @hostname )
      end

      def size
        @leaves.size
      end

      def status
        @leaves.each do |leaf|
          leaf.status
        end
      end
    end


    class PeerGroupComponent
      def initialize hostnames
        @peers = hostnames.map do |hostname|
          PeerComponent.new hostname
        end
      end

      def size
        @peers.size
      end

      def total
        count = 0
        @peers.each do |peer|
          count = count + peer.size
        end
        count
      end

      def ps
        @peers.each do |peer|
          peer.ps
        end
      end

      def start
        @peers.each do |peer|
          peer.start
        end
      end

      def stop
        @peers.each do |peer|
          peer.stop
        end
      end
    end


    class CxxxdGroupComponent
      def initialize hostnames
        @peers = hostnames.map do |hostname|
          CxxxdComponent.new hostname
        end
      end

      def size
        @peers.size
      end

      def total
        count = 0
        @peers.each do |peer|
          count = count + peer.size
        end
        count
      end

      def status
        @peers.each do |peer|
          peer.status
        end
      end
    end

  end
end