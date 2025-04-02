#
# Cookbook Name:: ocs
# Recipe:: submitter
#


group node[:ocs][:group][:name] do
  gid node[:ocs][:group][:gid]
  not_if "getent group #{node[:ocs][:group][:name]}"
end

user node[:ocs][:user][:name] do
  comment node[:ocs][:user][:description]
  uid node[:ocs][:user][:uid]
  gid node[:ocs][:user][:gid]
  home node[:ocs][:user][:home]
  shell node[:ocs][:user][:shell]
  not_if "getent passwd #{node[:ocs][:user][:name]}"
end

ocsroot = node[:ocs][:root]

link "/etc/profile.d/sgesettings.sh" do
  to "#{ocsroot}/default/common/settings.sh"
end

link "/etc/profile.d/sgesettings.csh" do
  to "#{ocsroot}/default/common/settings.csh"
end

link "/etc/cluster-setup.sh" do
  to "#{ocsroot}/default/common/settings.sh"
end

link "/etc/cluster-setup.csh" do
  to "#{ocsroot}/default/common/settings.csh"
end
