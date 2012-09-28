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

require 'castoro-pgctl/configurations_pgctl'
require 'castoro-pgctl/configurations_peer'

module Castoro
  module Peer

    module WorkingDirectoryExaminer
      class Base
        attr_reader :inactive, :active

        def initialize threshold
          @threshold = threshold
        end

        def traverse node, pattern  # :yield: path
          # Errno::ENOENT: No such file or directory - /xxx
          # Errno::EACCES: Permission denied - /root
          d = Dir.open node
          d.each do |x|
            next if x == "." or x == ".."
            if ( pattern.is_a?( Regexp ) and x.match( pattern ) ) or ( pattern.is_a?( String ) and x == pattern )
              yield "#{node}/#{x}"
            end
          end
        ensure
          d.close if defined? d
        end

        def examine
          @inactive, @active = 0, 0
        end
      end


      class DataDirectoryBase < Base
        def examine
          super
          # castoro-peer-2.0.0 or earlier
          #   /base_dir/999/baskets/w/20120820T15/100002.202.1.20120820T155450.924.870420
          #   /base_dir/999/baskets/r/20120802T17/100000.202.1.20120802T175508.475.443236
          #
          # castoro-peer-2.1.0 or later
          #   /base_dir/999/baskets/w/2012/20120820T15/100002.202.1.20120820T155450.924.870420
          #   /base_dir/999/baskets/r/2012/20120802T17/100000.202.1.20120802T175508.475.443236
          dir = Configurations::Peer.instance.basket_basedir
          traverse( dir, /\A\d+\Z/ ) do |v|
            traverse( v, "baskets" ) do |w|
              traverse( w, directory_name ) do |x|  # directory_name is defined in a subclass
                examine_sub x  # for 2.0.0 or earlier
                traverse( x, /\A\d+\Z/ ) do |z|  # for 2.1.0 or later
                  examine_sub z
                end
              end
            end
          end
        end

        private

        def count_up path
          # Errno::EACCES: Permission denied - /root/x
          s = File.stat path
          #p [s.ctime, path]
          if @threshold <= s.ctime.tv_sec  # in UNIX seconds
            @active = @active + 1
          else
            @inactive = @inactive + 1
          end
        end

        def examine_sub x
          traverse( x, /\A\d+T\d+\Z/ ) do |y|
            traverse( y, /\A[0-9a-z]+\./ ) do |path|  # could be /\A[0-9a-f]+\.\d+\.\d+\./
              count_up path
            end
          end
        end
      end


      class ForUploading < DataDirectoryBase
        def directory_name
          "w"
        end
      end


      class ForReceiving < DataDirectoryBase
        def directory_name
          "r"
        end
      end


      class ForSending < Base
        # @threshold is intentionally ignored.

        def examine
          super
          # /var/castoro/replication/processing
          # /var/castoro/replication/sleeping
          # /var/castoro/replication/waiting
          dir = "/var/castoro/replication"
          traverse( dir, /\A(processing|sleeping|waiting)\Z/ ) do |x|
            traverse( x, /\A[0-9a-f]+\./ ) do |path|  # could be /\A[0-9a-f]+\.\d+\.\d+\.(replicate|delete)/
              @active = @active + 1
            end
          end
        end
      end
    end

  end
end


if $0 == __FILE__
  module Castoro
    module Peer
      Configurations::Pgctl.file = "../../etc/castoro/pgctl.conf-sample-en.conf"
      #Configurations::Peer.file  = "../../../castoro-peer/etc/castoro/peer.conf-sample-en.conf"

      x = WorkingDirectoryExaminer::ForUploading.new
      x.examine
      p [x.inactive, x.active]

      x = WorkingDirectoryExaminer::ForReceiving.new
      x.examine
      p [x.inactive, x.active]

      x = WorkingDirectoryExaminer::ForSending.new
      x.examine
      p [x.inactive, x.active]
    end
  end
end
