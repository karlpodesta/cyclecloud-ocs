#
# Cookbook Name:: ocs
# Recipe:: autostart
#


# cron "autostart" do
#     command "#{node[:cyclecloud][:bootstrap]}/cron_wrapper.sh /usr/local/bin/azge autoscale -c /opt/cycle/ocs/autoscale.json"
#     only_if { node['cyclecloud']['cluster']['autoscale']['start_enabled'] }
# end
