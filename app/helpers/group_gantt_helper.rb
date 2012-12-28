module GroupGanttHelper
  class GroupGantt < Redmine::Helpers::Gantt    
    def initialize(options={})
      @month_from ||= Date.today.month - 1
      @year_from ||= Date.today.year
      if @month_from <= 0
        @month_from = 12
        @year_from -= 1
      end
      if @month_from > 12
        @month_from = 1
        @year_from += 1
      end
      
      options_months = (options[:months] || User.current.pref[:gantt_months]).to_i
      @calculate_date_range = !(options[:year] || options[:month])
      
      super(options)
      
      if @months != options_months
        @months = options_months > 48 ? 48 : options_months
        @date_to = (@date_from >> @months) - 1
      end
    end

    def common_params
      { :controller => 'group_gantt', :action => 'show', :project_id => @project }
    end
    
    def setup_dates
      if @calculate_date_range
        date_range = get_date_range()
        
        @date_from = date_range[0] << 1
        @date_to = date_range[1] >> 1
        @year_from = @date_from.year
        @month_from = @date_from.month        
        months = (@date_to.year*12+@date_to.month) - (@date_from.year*12+@date_from.month) + 1
        @months = months > 48 ? 48 : months      
        @date_from = Date.civil(@year_from, @month_from, 1)
        @date_to = (@date_from >> @months) - 1
      end
    end

    # TODO: top level issues should be sorted by start date
    def gantt_issue_compare(x, y, issues)      
      if @query.group_by == nil || @query.group_by == ""
        return [(x.root.start_date or x.start_date or Date.new()), x.root_id, (x.start_date or Date.new()), x.lft] <=> [(y.root.start_date or y.start_date or Date.new()), y.root_id, (y.start_date or Date.new()), y.lft]
      end
      
      if x.leaf? && !y.leaf? then
       return 1
      end

      if !x.leaf? && y.leaf? then
        return -1
      end

      return sort_group(x, y, issues)
    end

    def render_issues(issues, options={})
      if @query.group_by == nil || @query.group_by == ""
        super(issues, options)
        return
      end
      
      @issue_ancestors = []

      new_group = true
      group_start = options[:top] - options[:top_increment]
      group_max_line = 0
      group_write_line = group_max_line
      dates_in_line = [[]]
      last_shown_index = -1

      issues.each_with_index do |i, index|
        if i.start_date != nil
          if i.due_before == nil
            i.due_date = i.start_date
          end         
          
          if ((i.start_date >= @date_from || i.due_date >= @date_from) && i.start_date <= @date_to)
            new_group = last_shown_index < 0 || is_new_group(i, issues[last_shown_index]) || !i.leaf? || !issues[last_shown_index].leaf?
  
            if new_group
              options[:top] = group_start + ((group_max_line+1) * options[:top_increment])
              group_start = options[:top]
              group_max_line = 0
              group_write_line = group_max_line
              dates_in_line = [[]]
              @number_of_rows += 1
            else
              group_write_line = -1
              dates_in_line.each_with_index do |dates, line|
                if dates.find {|e| (i.start_date >= e[0] && i.start_date <= e[1]) || (i.start_date <= e[0] && i.due_before >= e[1]) } == nil
                 group_write_line = line
                  break
                end
              end
              if group_write_line == -1
                group_max_line += 1
                group_write_line = group_max_line
                dates_in_line.push([])
                @number_of_rows += 1
              end
            end
  
            options[:top] = group_start + (group_write_line * options[:top_increment])
            options[:no_title] = !new_group;
  
            subject_for_issue(i, options) unless options[:only] == :lines
            line_for_issue(i, options) unless options[:only] == :subjects
            
            last_shown_index = index  
            dates_in_line[group_write_line].push([i.start_date, i.due_before])
          end
        end

        break if abort?
      end

      options[:top] = group_start + ((group_max_line+1) * options[:top_increment])
      options[:indent] -= (options[:indent_increment] * @issue_ancestors.size)
    end

    def subject_for_issue(issue, options)
      if @query.group_by == nil || @query.group_by == ""
        super(issue, options)
        return
      end
      
      while @issue_ancestors.any? && !issue.is_descendant_of?(@issue_ancestors.last)
        @issue_ancestors.pop
        options[:indent] -= options[:indent_increment]
      end

      is_leaf = issue.leaf?
      group_name = get_group_name(issue)

      if !is_leaf
        subject_title = issue.subject
      else
        subject_title = group_name
      end

      if options[:no_title]
        subject_title = " "
      end

      output = case options[:format]
      when :html
        css_classes = ''
        css_classes << ' issue-overdue' if issue.overdue?
        css_classes << ' issue-behind-schedule' if issue.behind_schedule?
        css_classes << ' icon icon-issue' unless (Setting.gravatar_enabled? && issue.assigned_to) || options[:no_title]

        subject = "<span class='#{css_classes}'>".html_safe
        if !options[:no_title] && issue.assigned_to.present?
          assigned_string = l(:field_assigned_to) + ": " + issue.assigned_to.name
          subject << view.avatar(issue.assigned_to, :class => 'gravatar icon-gravatar', :size => 10, :title => assigned_string).to_s.html_safe
        end
        if !is_leaf
          subject << view.link_to_issue(issue).html_safe
        else
          subject << subject_title.html_safe
        end
        subject << '</span>'.html_safe
        html_subject(options, subject, :css => "issue-subject", :title => subject_title) + "\n"
      when :image
        image_subject(options, subject_title)
      when :pdf
        pdf_new_page?(options)
        pdf_subject(options, subject_title)
      end

      unless issue.leaf?
        @issue_ancestors << issue
        options[:indent] += options[:indent_increment]
      end

      output
    end

    def line_for_issue(issue, options)
      # Skip issues that don't have a due_before (due_date or version's due_date)
      if issue.is_a?(Issue)
        due_date = issue.due_before
        if !due_date
          due_date = issue.start_date
        end
        coords = coordinates(issue.start_date, due_date, issue.done_ratio, options[:zoom])
        #label = "#{ issue.status.name } #{ issue.done_ratio }%"
        label = " "

        case options[:format]
        when :html
          html_task(options, coords, :css => "task " + (issue.leaf? ? 'leaf' : 'parent'), :label => label, :issue => issue, :markers => !issue.leaf?)
        when :image
          image_task(options, coords, :label => label)
        when :pdf
          pdf_task(options, coords, :label => label)
      end
      else
        ActiveRecord::Base.logger.debug "GanttHelper#line_for_issue was not given an issue with a due_before"
        ''
      end
    end
    
    def pdf_task(params, coords, options={})
        height = options[:height] || 2

        # Renders the task bar, with progress and late
        if coords[:bar_start] && coords[:bar_end]
          params[:pdf].SetY(params[:top]+1.5)
          params[:pdf].SetX(params[:subject_width] + coords[:bar_start])
          params[:pdf].SetFillColor(200,200,200)
          length = coords[:bar_end] - coords[:bar_start]
          if length <= 0
            length = 1
          end
          params[:pdf].RDMCell(length, height, "", 0, 0, "", 1)

          if coords[:bar_late_end]
            params[:pdf].SetY(params[:top]+1.5)
            params[:pdf].SetX(params[:subject_width] + coords[:bar_start])
            params[:pdf].SetFillColor(255,100,100)
            length = coords[:bar_late_end] - coords[:bar_start]
            if length <= 0
              length = 1
            end
            params[:pdf].RDMCell(length, height, "", 0, 0, "", 1)
          end
          if coords[:bar_progress_end]
            params[:pdf].SetY(params[:top]+1.5)
            params[:pdf].SetX(params[:subject_width] + coords[:bar_start])
            params[:pdf].SetFillColor(90,200,90)
            length = coords[:bar_progress_end] - coords[:bar_start]
            if length <= 0
              length = 1
            end
            params[:pdf].RDMCell(length, height, "", 0, 0, "", 1)
          end
        end
        # Renders the markers
        if options[:markers]
          if coords[:start]
            params[:pdf].SetY(params[:top] + 1)
            params[:pdf].SetX(params[:subject_width] + coords[:start] - 1)
            params[:pdf].SetFillColor(50,50,200)
            params[:pdf].RDMCell(2, 2, "", 0, 0, "", 1)
          end
          if coords[:end]
            params[:pdf].SetY(params[:top] + 1)
            params[:pdf].SetX(params[:subject_width] + coords[:end] - 1)
            params[:pdf].SetFillColor(50,50,200)
            params[:pdf].RDMCell(2, 2, "", 0, 0, "", 1)
          end
        end
        # Renders the label on the right
        if options[:label]
          params[:pdf].SetX(params[:subject_width] + (coords[:bar_end] || 0) + 5)
          params[:pdf].RDMCell(30, 2, options[:label])
        end
      end
    
private

    def is_new_group(x, y)
      value_x = @query.group_by_column.value(x)
      value_y = @query.group_by_column.value(y)
            
      return value_x != value_y
    end

    def get_group_name(issue)      
      result = @query.group_by_column.value(issue)

      if result == nil || result == ''
        return 'None'
      end

      return result.to_s
    end

    def sort_group(x, y, issues)
      value_x = @query.group_by_column.value(x)
      value_y = @query.group_by_column.value(y)

      if value_x == nil && value_y == nil
        return [(x.root.start_date or x.start_date or Date.new()), x.root_id, (x.start_date or Date.new()), x.lft] <=> [(y.root.start_date or y.start_date or Date.new()), y.root_id, (y.start_date or Date.new()), y.lft]
      end

      if value_x == nil
        return -1
      end

      if value_y == nil
        return 1
      end

      if value_x == value_y
        return [(x.root.start_date or x.start_date or Date.new()), x.root_id, (x.start_date or Date.new()), x.lft] <=> [(y.root.start_date or y.start_date or Date.new()), y.root_id, (y.start_date or Date.new()), y.lft]
      end

      return  value_x <=> value_y
    end
    
    def get_date_range()      
      min = nil
      max = nil
      projects.each do |p|
        all_issues = project_issues(p)
        
        all_issues.each do |i|
          if min == nil || (i.start_date != nil && min > i.start_date)
            min = i.start_date
          end
          if min == nil || (i.due_before != nil && min > i.due_before)
            min = i.due_before
          end
          if max == nil || (i.start_date != nil && max < i.start_date)
            max = i.start_date
          end
          if max == nil || (i.due_before != nil && max < i.due_before)
            max = i.due_before
          end
        end
      end
      
      if min == nil && max == nil
          min = Date.today
          max = Date.today
      end
      
      return [min, max]
    end
  end
end
