# Fat Free CRM
# Copyright (C) 2008-2009 by Michael Dvorkin
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
# 
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http:#www.gnu.org/licenses/>.
#------------------------------------------------------------------------------

module FatFreeCRM
  class Tabs
    cattr_accessor :main
    cattr_accessor :admin

    if ENV['RAILS_ENV'] && ActiveRecord::Base.connection.tables.include?("settings")
      @@main  = Setting[:tabs]
      @@admin = Setting[:admin_tabs]
    end

    #----------------------------------------------------------------------------
    def self.list(which_ones = :main)
      case which_ones
        when :main  then @@main
        when :admin then @@admin
        else raise ArgumentError.new("#{which_one} is invalid tab argument, use :main or :admin")
      end
    end

  end
end