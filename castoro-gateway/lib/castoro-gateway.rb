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

require "rubygems"
gem "castoro-common", ">=2.0.0"
require "castoro-common"

require "castoro-gateway/utils"
require "castoro-gateway/cache"
require "castoro-gateway/configuration"
require "castoro-gateway/cache_helper"
require "castoro-gateway/facade"
require "castoro-gateway/repository"
require "castoro-gateway/workers"
require "castoro-gateway/console_server"
require "castoro-gateway/watchdog_sender"
require "castoro-gateway/master_workers"
require "castoro-gateway/version"

require "castoro-gateway/gateway"
