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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#------------------------------------------------------------------------------

class Task < ActiveRecord::Base
  attr_accessor :calendar

  has_many :activities, :as => :subject, :dependent => :destroy
  belongs_to  :asset, :polymorphic => true
  belongs_to  :assignee, :class_name => "User", :foreign_key => :assigned_to
  belongs_to  :completor, :class_name => "User", :foreign_key => :completed_by
  belongs_to  :user

  named_scope :ordered, :order => "due_at DESC"

  named_scope :my, lambda { |user| { :conditions => [ "(user_id = ? AND assigned_to IS NULL) OR assigned_to = ?", user.id, user.id ], :include => :assignee } }

  named_scope :assigned_by, lambda { |user| { :conditions => [ "user_id = ? AND assigned_to IS NOT NULL AND assigned_to != ?", user.id, user.id ], :include => :assignee } }

  named_scope :tracked_by, lambda { |user| { :conditions => [ "user_id = ? OR assigned_to = ?", user.id, user.id ], :include => :assignee } }

  named_scope :pending,       :conditions => "completed_at IS NULL", :order => "due_at, id"
  named_scope :assigned,      :conditions => "completed_at IS NULL AND assigned_to IS NOT NULL", :order => "due_at, id"
  named_scope :completed,     :conditions => "completed_at IS NOT NULL", :order => "completed_at DESC"

  named_scope :due_asap,      :conditions => "due_at IS NULL AND bucket = 'due_asap'", :order => "id DESC"
  named_scope :overdue,       lambda { { :conditions => [ "due_at IS NOT NULL AND due_at < ?", Time.current ], :order => "id DESC" } }
  named_scope :due_today,     lambda { { :conditions => [ "due_at >= ? AND due_at < ?", Time.current, Time.current.tomorrow.at_beginning_of_day ], :order => "id DESC" } }
  named_scope :due_tomorrow,  lambda { { :conditions => [ "due_at >= ? AND due_at < ?", Time.current.tomorrow.at_beginning_of_day, Time.current.tomorrow.at_beginning_of_day + 1.day ], :order => "id DESC" } }
  named_scope :due_this_week, lambda { { :conditions => [ "due_at >= ? AND due_at < ?", Time.current.tomorrow.at_beginning_of_day + 1.day, Time.current.at_beginning_of_day.next_week ], :order => "id DESC" } }
  named_scope :due_next_week, lambda { { :conditions => [ "due_at >= ? AND due_at < ?", Time.current.at_beginning_of_day.next_week, Time.current.at_beginning_of_day.next_week.end_of_week + 1.day ], :order => "id DESC" } }
  named_scope :due_later,     lambda { { :conditions => [ "(due_at IS NULL AND bucket = 'due_later') OR due_at >= ?", Time.current.at_beginning_of_day.next_week.end_of_week + 1.day ], :order => "id DESC" } }

  named_scope :completed_today,      lambda { { :conditions => [ "completed_at >= ? AND completed_at < ?", Time.current.at_beginning_of_day, Time.current.tomorrow.at_beginning_of_day ] } }
  named_scope :completed_yesterday,  lambda { { :conditions => [ "completed_at >= ? AND completed_at < ?", Time.current.yesterday.at_beginning_of_day, Time.current.at_beginning_of_day ] } }
  named_scope :completed_this_week,  lambda { { :conditions => [ "completed_at >= ? AND completed_at < ?", Time.current.at_beginning_of_day.beginning_of_week , Time.current.yesterday.at_beginning_of_day ] } }
  named_scope :completed_last_week,  lambda { { :conditions => [ "completed_at >= ? AND completed_at < ?", Time.current.at_beginning_of_day.beginning_of_week - 7.days, Time.current.at_beginning_of_day.beginning_of_week ] } }
  named_scope :completed_this_month, lambda { { :conditions => [ "completed_at >= ? AND completed_at < ?", Time.current.at_beginning_of_day.beginning_of_month, Time.current.at_beginning_of_day.beginning_of_week - 7.days ] } }
  named_scope :completed_last_month, lambda { { :conditions => [ "completed_at >= ? AND completed_at < ?", (Time.current.at_beginning_of_day.beginning_of_month - 1.day).beginning_of_month, Time.current.at_beginning_of_day.beginning_of_month] } }

  named_scope :service_plan_items, :conditions => ["category = ? and show_in_report = ?", "csp", true], :order => ["completed_at DESC"]
  named_scope :reportable, :conditions => ["show_in_report = ?", true], :order => ["completed_at DESC"]

  validates_presence_of :user_id
  validates_presence_of :name, :message => "^Please specify task name."
  validates_presence_of :calendar, :if => "self.bucket == 'specific_time'"
  validate              :specific_time
  validates_presence_of :recurring_period, :if => :is_recurring

  before_create :set_due_date
  before_update :set_due_date

  acts_as_reportable

  # for active_scaffold
  def to_label
    "Task #{self.id}"
  end

  def my?(user)
    (self.user == user && assignee.nil?) || assignee == user
  end

  def assigned_by?(user)
    self.user == user && assignee && assignee != user
  end

  def tracked_by?(user)
    self.user == user || self.assignee == user
  end

  def computed_bucket
    return self.bucket if self.bucket != "specific_time"
    case
    when self.due_at < Time.current.at_beginning_of_day
      "overdue"
    when self.due_at >= Time.current.at_beginning_of_day && self.due_at < Time.current.tomorrow.at_beginning_of_day
      "due_today"
    when self.due_at == Time.current.tomorrow.at_beginning_of_day && self.due_at < (Time.current.tomorrow.at_beginning_of_day + 1.day).to_time
      "due_tomorrow"
    when self.due_at >= (Time.current.tomorrow.at_beginning_of_day + 1.day).to_time && self.due_at < Time.current.at_beginning_of_day.next_week.to_time
      "due_this_week"
    when self.due_at >= Time.current.at_beginning_of_day.next_week.to_time && self.due_at < (Time.current.at_beginning_of_day.next_week.end_of_week + 1.day).to_time
      "due_next_week"
    else
      "due_later"
    end
  end

  def self.find_all_grouped(user, view)
    settings = ""
    if view == "completed"
      settings = [["Today", :completed_today], ["Yesterday", :completed_yesterday], ["Last week", :completed_last_week], ["This month", :completed_this_month], ["Last month", :completed_last_month]]
    else
      settings = [["Overdue", :overdue], ["As Soon As Possible", :due_asap], ["Today", :due_today], ["Tomorrow", :due_tomorrow], ["This Week", :due_this_week], ["Next Week", :due_next_week], ["Sometime Later", :due_later]]
    end
    settings.inject({}) do |hash, (value, key)|
      hash[key] = (view == "assigned" ? assigned_by(user).send(key).pending : my(user).send(key).send(view))
      hash
    end
  end

  def self.bucket_empty?(bucket, user, view = "pending")
    return false if bucket.blank?
    if view == "assigned"
      assigned_by(user).send(bucket).pending.count
    else
      my(user).send(bucket).send(view).count
    end == 0
  end

  def self.totals(user, view = "pending")
    settings = (view == "completed" ? [["Today", :completed_today], ["Yesterday", :completed_yesterday], ["Last week", :completed_last_week], ["This month", :completed_this_month], ["Last month", :completed_last_month]] : [["Overdue", :overdue], ["As Soon As Possible", :due_asap], ["Today", :due_today], ["Tomorrow", :due_tomorrow], ["This Week", :due_this_week], ["Next Week", :due_next_week], ["Sometime Later", :due_later]])
    settings.inject({ :all => 0 }) do |hash, (value, key)|
      hash[key] = (view == "assigned" ? assigned_by(user).send(key).pending.count : my(user).send(key).send(view).count)
      hash[:all] += hash[key]
      hash
    end
  end

  private
  def set_due_date
    self.due_at = case self.bucket
    when "overdue"
      self.due_at || Time.current.yesterday.at_beginning_of_day
    when "due_today"
      Date.today
    when "due_tomorrow"
      self.calendar = (Time.current + 1.day).at_beginning_of_day.strftime("%B %d %Y %H:%M:%S")
      Chronic.time_class = Time.zone
      self.due_at = Chronic.parse(self.calendar)
      self.due_at
    when "due_four_days"
      self.due_at = Time.current + 4.days
      self.bucket = "specific_time"
      self.calendar = self.due_at.strftime("%B %d %Y %H:%M:%S")
      self.due_at
    when "due_this_week"
      Date.today.end_of_week
    when "due_one_week"
      self.due_at = Time.current + 1.week
      self.bucket = "specific_time"
      self.calendar = self.due_at.strftime("%B %d %Y %H:%M:%S")
      self.due_at
    when "due_next_week"
      Time.current.next_week.end_of_week
    when "due_two_weeks"
      self.due_at = Time.current + 14.days
      self.bucket = "specific_time"
      self.calendar = self.due_at.strftime("%B %d %Y %H:%M:%S")
      self.due_at
    when "due_one_month"
      self.due_at = Time.current + 1.month
      self.bucket = "specific_time"
      self.calendar = self.due_at.strftime("%B %d %Y %H:%M:%S")
      self.due_at
    when "due_six_months"
      self.due_at = Time.current + 6.months
      self.bucket = "specific_time"
      self.calendar = self.due_at.strftime("%B %d %Y %H:%M:%S")
      self.due_at
    when "due_later"
      Time.current + 100.years
    when "specific_time"
      Chronic.time_class = Time.zone
      self.due_at = Chronic.parse(self.calendar)
    else 
      nil
    end
  end

  def specific_time
    self.calendar.gsub!(/,/,"") if !calendar.nil?
    Chronic.time_class = Time.zone
    if (self.bucket == "specific_time") && (::Chronic.parse(self.calendar).nil?)
      errors.add(:calendar, "^Please specify valid date.")
    end
  end

end
