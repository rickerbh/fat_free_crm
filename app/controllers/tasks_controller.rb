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

require 'icalendar'

class TasksController < ApplicationController
  before_filter :login_required
  before_filter :update_sidebar, :only => :index
  
  def ical
    @cal = Icalendar::Calendar.new
    current_user.tasks.find(:all).each do |t|
      event = Icalendar::Event.new
      event.start = t.due_at.to_date
      event.end = t.due_at.to_date
      description = t.name
      description << " (#{t.asset.full_name})" if t.asset
      event.summary = description
      @cal.add event
    end
    send_data @cal.to_ical, :filename => "calendar.ics", :type => "text/calendar"
  end
  
  def index
    @view = params[:view] || "pending"
    @tasks = Task.scoped(:include => [:user, :asset]).find_all_grouped(@current_user, @view)

    respond_to do |format|
      format.html 
      format.xml  { render :xml => @tasks.inject({}) { |tasks, (k,v)| tasks[k.to_s] = v; tasks } }
    end
  end

  def show
    respond_to do |format|
      format.html { render :action => :index }
      format.xml  { @task = Task.tracked_by(@current_user).find(params[:id]);  render :xml => @task }
    end
  end

  def new
    @view = params[:view] || "pending"
    @task = Task.new
    @users = []    @bucket = [["As Soon As Possible", :due_asap], ["Tomorrow", :due_tomorrow], ["4 Days", :due_four_days], ["1 Week", :due_one_week], ["2 Weeks", :due_two_weeks], ["1 Month", :due_one_month], ["6 Months", :due_six_months], ["On Specific Date...", :specific_time]]
    @category = [["Appraisal", :appraisal], ["Buyer networking", :buyer_networking], ["Email", :email], ["Listing presentation", :listing_presentation], ["Networking", :networking], ["Placing signage", :placing_signage], ["Prospecting call", :prospecting_call], ["Send letter", :send_letter], ["Vendor Meeting", :vendor_meeting]]
    if params[:related]
      model, id = params[:related].split("_")
      instance_variable_set("@asset", model.classify.constantize.my(@current_user).find(id))
    end

    respond_to do |format|
      format.js  
      format.xml  { render :xml => @task }
    end

  rescue ActiveRecord::RecordNotFound
    respond_to_related_not_found(model, :js) if model
  end

  def edit
    @view = params[:view] || "pending"
    @task = Task.tracked_by(@current_user).find(params[:id])
    @users = User.except(@current_user).all
    @bucket = [["As Soon As Possible", :due_asap], ["Tomorrow", :due_tomorrow], ["4 Days", :due_four_days], ["1 Week", :due_one_week], ["2 Weeks", :due_two_weeks], ["1 Month", :due_one_month], ["6 Months", :due_six_months]][1..-1] << [ "On Specific Date...", :specific_time ]
    @category = [["Appraisal", :appraisal], ["Buyer networking", :buyer_networking], ["Email", :email], ["Listing presentation", :listing_presentation], ["Networking", :networking], ["Phone call - Buyer", :phone_call_buyer], ["Placing signage", :placing_signage], ["Prospecting call", :prospecting_call], ["Send letter", :send_letter], ["Vendor Meeting", :vendor_meeting]]
    @asset = @task.asset if @task.asset_id?
    if params[:previous] =~ /(\d+)\z/
      @previous = Task.tracked_by(@current_user).find($1)
    end

  rescue ActiveRecord::RecordNotFound
    @previous ||= $1.to_i
    respond_to_not_found(:js) unless @task
  end

  def create
    if params[:task][:is_recurring]
      if params[:period] == "1"
        params[:task][:recurring_period] = 1440 * params[:period_count].to_i
      elsif params[:period] == "2"
        params[:task][:recurring_period] = 10080 * params[:period_count].to_i
      elsif params[:period] == "3"
        params[:task][:recurring_period] = 43829 * params[:period_count].to_i
      elsif params[:period] == "4"
        params[:task][:recurring_period] = 525948 * params[:period_count].to_i
      end
    end

    @task = Task.create(params[:task])
    @view = params[:view] || "pending"

    respond_to do |format|
      if @task.errors.empty?
        update_sidebar if called_from_index_page?
        format.js   
        format.xml  { render :xml => @task, :status => :created, :location => @task }
      else
        format.js  
        format.xml  { render :xml => @task.errors, :status => :unprocessable_entity }
      end
    end
  end
  
  def update
    @view = params[:view] || "pending"
    @task = Task.tracked_by(@current_user).find(params[:id])
    @task_before_update = @task.clone

    if @task.due_at && (@task.due_at < Date.today.to_time)
      @task_before_update.bucket = "overdue"
    else
      @task_before_update.bucket = @task.computed_bucket
    end

    respond_to do |format|
      if @task.update_attributes(params[:task])
        @task.bucket = @task.computed_bucket
        if called_from_index_page?
          if Task.bucket_empty?(@task_before_update.bucket, @current_user, @view)
            @empty_bucket = @task_before_update.bucket
          end
          update_sidebar
        end
        format.js  
        format.xml  { head :ok }
      else
        format.js 
        format.xml  { render :xml => @task.errors, :status => :unprocessable_entity }
      end
    end

  rescue ActiveRecord::RecordNotFound
    respond_to_not_found(:js, :xml)
  end

  def destroy
    @view = params[:view] || "pending"
    @task = Task.tracked_by(@current_user).find(params[:id])
    @task.destroy if @task

    if Task.bucket_empty?(params[:bucket], @current_user, @view)
      @empty_bucket = params[:bucket]
    end

    update_sidebar if called_from_index_page?
    respond_to do |format|
      format.js
      format.xml  { head :ok }
    end

  rescue ActiveRecord::RecordNotFound
    respond_to_not_found(:js, :xml)
  end

  def complete
    @task = Task.tracked_by(@current_user).find(params[:id])

    if @task.is_recurring
      unless @task.recurring_end_date.nil?
        if @task.recurring_end_date > @task.due_at + @task.recurring_period.minutes
          # Create a new task because the end date isn't up yet
          @task_copy = @task.clone
          @task_copy.due_at = @task_copy.due_at + @task_copy.recurring_period.minutes
          @task_copy.calendar = @task_copy.due_at.strftime("%B %d %Y %H:%M:%S")
          @task_copy.updated_at = ::Time.now
          @task_copy.save!
        else
          # task is recurring, but end date has passed.  
          # task will be closed later in this method
        end
      else
        # task is recurring, but does not have an end date (recurrs forever)
        # Create the replacement task, close the original, no end date on replacement
        @task_copy = @task.clone
        @task_copy.due_at = @task_copy.due_at + @task_copy.recurring_period.minutes
        @task_copy.calendar = @task_copy.due_at.strftime("%B %d %Y %H:%M:%S")
        @task_copy.updated_at = ::Time.now
        @task_copy.save!
      end
    end
    if @task.bucket == "due_asap"
      @task.update_attributes(:completed_at => Time.now, :completed_by => @current_user.id, :calendar => Time.now.strftime("%B %d %Y %H:%M:%S")) if @task
    else
      @task.update_attributes(:completed_at => Time.now, :completed_by => @current_user.id, :calendar => @task.due_at.strftime("%B %d %Y %H:%M:%S")) if @task
    end

    if Task.bucket_empty?(params[:bucket], @current_user)
      @empty_bucket = params[:bucket]
    end

    update_sidebar unless params[:bucket].blank?
    respond_to do |format|
      format.js  
      format.xml  { head :ok }
    end

  rescue ActiveRecord::RecordNotFound
    respond_to_not_found(:js, :xml)
  end

  def filter
    @view = params[:view] || "pending"

    update_session do |filters|
      if params[:checked] == "true"
        filters << params[:filter]
      else
        filters.delete(params[:filter])
      end
    end
  end

  private
  def update_session
    name = "filter_by_task_#{@view}"
    filters = (session[name].nil? ? [] : session[name].split(","))
    yield filters
    session[name] = filters.uniq.join(",")
  end

  def update_sidebar
    @view = params[:view]
    @view = "pending" unless %w(pending assigned completed).include?(@view)
    @task_total = Task.totals(@current_user, @view)

    if @task
      update_session do |filters|
        if @empty_bucket  
          filters.delete(@empty_bucket)
        elsif !@task.deleted_at && !@task.completed_at
          filters << @task.computed_bucket
        end
      end
    end

    name = "filter_by_task_#{@view}"
    unless session[name]
      filters = @task_total.keys.select { |key| key != :all && @task_total[key] != 0 }.join(",")
      session[name] = filters unless filters.blank?
    end
  end

end
