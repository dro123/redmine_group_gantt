# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

match '/projects/:project_id/issues/group_gantt', :to => 'group_gantt#show'
match '/group_gantt', :to => 'group_gantt#show'