require 'group_gantt_hook_listener'

Redmine::Plugin.register :redmine_group_gantt do
  name 'Redmine Group Gantt plugin'
  author 'Tobias Droste'
  description 'This is a plugin for Redmine that enables grouping in Gantt diagrams'
  version '0.0.1'
  requires_redmine :version_or_higher => '2.0.0'
  #url 'http://example.com/path/to/plugin'
  #author_url 'http://example.com/about'

  project_module :group_gantt do
    permission :show_group_gantt, { :group_gantt => [:show] }
  end
  menu :project_menu, :group_gantt, { :controller => 'group_gantt', :action => 'show' }, :caption => :plugin_title, :after => :gantt, :param => :project_id
end
