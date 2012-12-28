class GroupGanttController < ApplicationController
  unloadable

  menu_item :group_gantt
  before_filter :find_optional_project

  rescue_from Query::StatementInvalid, :with => :query_statement_invalid

  helper :gantt
  helper :issues
  helper :projects
  helper :queries
  include QueriesHelper
  helper :sort
  include SortHelper
  include Redmine::Export::PDF

  def show
    if params.has_key?(:project_id)
      @project = Project.find(params[:project_id])
    else
      @project = nil
    end
    @gantt = GroupGanttHelper::GroupGantt.new(params)
    @gantt.project = @project
    retrieve_query
    @gantt.query = @query if @query.valid?

    basename = (@project ? "#{@project.identifier}-" : '') + 'group_gantt'

    respond_to do |format|
      format.html { render :action => "show", :layout => !request.xhr? }
      format.png  { send_data(@gantt.to_image, :disposition => 'inline', :type => 'image/png', :filename => "#{basename}.png") } if @gantt.respond_to?('to_image')
      format.pdf  { send_data(@gantt.to_pdf, :type => 'application/pdf', :filename => "#{basename}.pdf") }
    end
  end
end
