class GroupGanttHookListener < Redmine::Hook::ViewListener
  render_on :view_issues_sidebar_planning_bottom, :partial => "group_gantt/issues_sidebar" 
end