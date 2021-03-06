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

module Castoro
  class Gateway
    ##
    # Castoro::Gateway's worker threads.
    #
    class Workers < Castoro::Workers

      def initialize logger, count, facade, repository, multicast_addr, device_addr, multicast_port, island
        super logger, count
        @facade     = facade
        @repository = repository
        @addr       = multicast_addr # This is multicast address, not IP address
        @device     = device_addr    # This is IP Address of NIC
        @port       = multicast_port
        @island     = island ? island.to_island : nil
      end

    private

      def work
        Sender::UDP::Multicast.new(@logger, @port, @addr, @device) { |s|
          nop = Protocol::Response::Nop.new(nil)

          until Thread.current[:dying]
            begin
              if (recv_ret = @facade.recv)
                h, d = recv_ret

                case d
                when Protocol::Command::Create
                  res = @repository.fetch_available_peers d, @island
                  s.send h, res, h.ip, h.port

                when Protocol::Command::Get
                  d = Protocol::Command::Get.new(d.basket, @island) if @island and d.island.nil?
                  if @island == d.island
                    res = @repository.query d
                    if res
                      s.send h, res, h.ip, h.port

                      # A packet relay is carried out when peers is less than the specified number.
                      @repository.if_replication_is_insufficient(res.paths.keys) { s.multicast h, d }
                    else
                      s.multicast h, d
                    end
                  end

                when Protocol::Command::Insert
                  @repository.insert_cache_record d

                when Protocol::Command::Drop
                  @repository.drop_cache_record d

                when Protocol::Command::Alive
                  @repository.update_watchdog_status d

                when Protocol::Command::Nop
                  s.send h, nop, h.ip, h.port

                else
                  # do nothing.
                end

              end

            rescue => e
              @logger.error { e.message }
              @logger.debug { e.backtrace.join("\n\t") }
            end
          end
        }
      end

    end
  end
end
