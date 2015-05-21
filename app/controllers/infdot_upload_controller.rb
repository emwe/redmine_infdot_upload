#  Copyright (C) 2010-2015 Raivo Laanemets, 2014 Jarosław Jeleniewicz
#
#  This file is part of infdot-build.
#  This file is part of infdot-upload.
#
#  Infdot-build is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  Infdot-build is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with infdot-build.  If not, see <http://www.gnu.org/licenses/>.
 
class InfdotUploadController < ActionController::Base
  
  # Response has empty/nil error
  # message in the case of no error.
  
  class Response
    def initialize message
      @errorMessage = message
    end
  end
  
  # Handles the query for the file upload.
  
  def upload
    setup_essential_data params
    
    if params[:file].nil?
      @errors << "The file to store is not sent."
    end
    
    if @errors.empty?
      # Duplicates sanitize_filename in attachment.rb
      original_name = params[:file].original_filename
      original_name = original_name.gsub(/^.*(\\|\/)/, '')
      original_name = original_name.gsub(/[^\w\.\-]/,'_')
      @version.attachments.each do |a|
        if a.filename == original_name
          @errors << "The file already exists."
        end
      end
    end
    
    if @errors.empty?
      begin
        # There was a comment that Attachment#create might be moved into the model.
        a = Attachment.create(
          :container => @version,
          :file => params[:file],
          :description => "", # Description is not shown under Files anyway.
          :author => @user)
        
        if a.new_record?
          @errors << "File was not saved."
        end
      rescue Exception => e
        @errors << "Cannot store file: #{e.message}."
      end
    end
    
    if @errors.empty?
      if Setting.notified_events.include?('file_added')
        Mailer.attachments_added([a]).deliver
      end
      render :json => Response.new(nil)
    else
      render :json => Response.new(@errors.join(" "))
    end
  end
  
  private
  
  # Validates user name/password and project.
  # Checks if the user has permission to manage files.
  
  def setup_essential_data params
    @errors = []
   
    if params[:api_key].nil? and params[:user].nil? 
      @errors << "Neither API key nor user name specified."
    end
    
    if !params[:user].nil? and params[:password].nil?
      @errors << "User password is not specified."
    end
    
    if params[:project].nil?
      @errors << "Project identifier is not specified."
    end

    if params[:version_id].nil?
      @errors << "Version identifier is not specified."
    end
    
    if @errors.empty?
      unless params[:api_key].nil?
        @user = User.find_by_api_key params[:api_key]
        if @user.nil?
          @errors << "API key is invalid."
        end
      else
        @user = User.find_by_login params[:user]
        if @user.nil?
          @errors << "User name is invalid."
        else
          if !@user.check_password? params[:password]
            @errors << "Incorrect username/password."
          end
        end
      end
    end
    
    if @errors.empty?
      @project = Project.find_by_identifier params[:project]
      if @project.nil?
        @errors << "Project name is invalid."
      end
    end

    if @errors.empty?
      @project.versions.each do |version|
        if version.id = params[:version_id]
          @version = version
        end
      end
      if @version.nil?
        @errors << "Version ID is invalid or does not belong to project specified."
      end
    end
    
    if @errors.empty?
      if !can_upload_file @user, @project
        @errors << "No permissions to manage files."
      end
    end
  end
  
  # Checks whether the user has sufficient
  # permissions to manage files.
  
  def can_upload_file user, project
    roles = user.roles_for_project project
    can_upload = false
    roles.each do |r|
      can_upload ||= r.permissions.include? :manage_files
    end
  end
  
end
