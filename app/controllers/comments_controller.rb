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

class CommentsController < ApplicationController
  before_filter :login_required
  COMMENTABLE = %w(client_id listing_id).freeze

  def new
    @comment = Comment.new
    @comment.activity_type = ""
    @commentable = extract_commentable_name(params)
    if @commentable
      update_commentable_session
    end

    respond_to do |format|
      format.js
      format.xml  { render :xml => @comment }
    end

  rescue ActiveRecord::RecordNotFound
    respond_to_related_not_found(@commentable, :js)
  end

  def create
    @comment = Comment.new(params[:comment])
    @show_comment = "false".eql?(params[:show_comment]) ? false : true
    @comment.user = current_user

    unless @comment.commentable
      raise ActiveRecord::RecordNotFound
    end

    respond_to do |format|
      if @comment.save
        format.js
        format.xml  { render :xml => @comment, :status => :created, :location => @comment }
      else
        format.js
        format.xml  { render :xml => @comment.errors, :status => :unprocessable_entity }
      end
    end

  rescue ActiveRecord::RecordNotFound
    respond_to_related_not_found(params[:comment][:commentable_type].downcase, :js, :xml)
  end

  def destroy
    @comment = current_user.comments.find(params[:id])
    @comment.destroy if @comment

    respond_to do |format|
      format.html { redirect_to :back }
      format.js
      format.xml
    end

  rescue ActiveRecord::RecordNotFound
    respond_to_not_found(:html, :js, :xml)
  end

  private
  def extract_commentable_name(params)
    commentable = (params.keys & COMMENTABLE).first
    commentable.sub("_id", "") if commentable
  end

  def update_commentable_session
    if params[:cancel] == "true"
      session.delete("#{@commentable}_new_comment")
    else
      session["#{@commentable}_new_comment"] = true
    end
  end
end
