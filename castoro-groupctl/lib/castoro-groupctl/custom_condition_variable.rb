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

module Castoro
  module Peer

    # This class is a working alternative to ConditionVariable in 
    # /usr/local/lib/ruby/1.9.1/thread.rb which does not work efficiently.

    # Note that this code is tuned for ruby-1.9.1-p378/thread.c.
    # This might not appropriately work with other than Ruby 1.9.1

    # ConditionVariable#wait does not wait: 
    # Bug of Ruby: http://redmine.ruby-lang.org/issues/show/3212

    class CustomConditionVariable
      def initialize
        @sleepers = []
        @mutex = Mutex.new
      end

      def wait mutex
        @mutex.synchronize do
          @sleepers.push Thread.current
        end
        mutex.sleep
      end

      def timedwait mutex, duration
        @mutex.synchronize do
          @sleepers.push Thread.current
        end
        mutex.sleep duration  # there is no way to determine whether waked up or timed out.
        tid = @mutex.synchronize do
          @sleepers.delete Thread.current  # remove the current thread if it is included.
        end
        #  this method returns :etimedout if timed out occured or Thread.current 
        #  gets waked up by the outsize of this class.
        #  this returns nil if Thread.current gets waked up by a signal or broadcast.
        tid ? :etimedout : nil
      end

      def signal
        @mutex.synchronize do
          begin
            t = @sleepers.shift
            t.wakeup if t
          rescue ThreadError
            retry
          end
        end
      end

      def broadcast
        @mutex.synchronize do
          loop do
            t = @sleepers.shift or break
            begin
              t.wakeup
            rescue ThreadError
            end
          end
        end
      end
    end

  end
end
