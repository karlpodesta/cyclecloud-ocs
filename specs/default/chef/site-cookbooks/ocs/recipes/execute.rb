#
# Cookbook Name:: ocs
# Recipe:: execute
#
include_recipe "ocs::_updatehostname"
include_recipe "ocs::sgefs" if node[:ocs][:managed_fs]
include_recipe "ocs::submitter"

ocsroot = node[:ocs][:root]
ocscell = node[:ocs][:cell]

# nodename assignments in the resouce blocks in this recipe are delayed till
# the execute phase by using the lazy evaluation.
# This accomodates run lists that change the hostname of the node.

myplatform=node[:platform]

package 'Install binutils' do
  package_name 'binutils'
end

package 'Install hwloc' do
  package_name 'hwloc'
end

case myplatform
when 'ubuntu'
  package 'Install libnuma' do
    package_name 'libnuma-dev'
#  when 'centos'
#    package_name 'whatevercentoscallsit'
  end
end

shared_bin = node[:ocs][:shared][:bin]

if not(shared_bin)
  directory ocsroot do
    owner node[:ocs][:user][:uid]
    group node[:ocs][:user][:gid]
    mode "0755"
    action :create
    recursive true
  end
  
  include_recipe "::_install"
end


myplatform=node[:platform]
myplatform = "centos" if node[:platform_family] == "rhel" # TODO: fix this hack for redhat
nodename = node[:cyclecloud][:instance][:hostname]
nodename_short = nodename.split(".")[0]

# default case systemd
sge_services = ["sgeexecd", "sgemasterd"]
sge_service_names = []
sge_services.each do |sge_service|
  sge_service_template="#{sge_service}.service.erb"
  sge_service_name="#{sge_service}.service"
  sge_service_initfile="/etc/systemd/system/#{sge_service_name}"
  # edge case sysvinit
  case node['platform_family']
  when 'rhel'
    if node['platform_version'].to_i <= 6
      sge_service_template="#{sge_service}.erb"
      sge_service_name=sge_service
      sge_service_initfile="/etc/init.d/#{sge_service}"
    end
  end

  template sge_service_initfile do
    source sge_service_template
    mode 0755
    owner "root"
    group "root"
    variables(
      :ocsroot => ocsroot,
      :ocscell => ocscell
    )
  end
  sge_service_names.push(sge_service_name)
end

sge_execd_service = sge_service_names[0]
sge_qmasterd_service = sge_service_names[1]


directory "/etc/acpi/events" do
  recursive true
end
cookbook_file "/etc/acpi/events/preempted" do
  source "conf/preempted"
  mode "0644"
end

cookbook_file "/etc/acpi/preempted.sh" do
  source "sbin/preempted.sh"
  mode "0755"
end

ocs_settings = "/etc/cluster-setup.sh"

# Store node conf file to local disk to avoid requiring shared filesystem
template "#{Chef::Config['file_cache_path']}/compnode.conf" do
  source "compnode.conf.erb"
  variables lazy {
    {
      :ocsroot => ocsroot,
      :nodename => node[:hostname],
      :ocsclustername => node[:ocs][:sge_cluster_name],
      :ocscell => ocscell,
      :ocs_gid_range => node[:ocs][:gid_range],
      :ocs_admin_mail => node[:ocs][:admin_mail],
      :ocs_shadow_host => node[:ocs][:shadow_host],
      :execd_spool_dir => node[:ocs][:execd_spool_dir],
      :qmaster_spool_dir => node[:ocs][:qmaster_spool_dir],
      :ocs_spooling_method => node[:ocs][:spooling_method],
      :ocs_qmaster_port => node[:ocs][:sge_qmaster_port],
      :ocs_execd_port => node[:ocs][:sge_execd_port]
    }
  }
end

# force node.json to be rewritten, then trigger a jetpack log message to update the hostname
execute "trigger dump node.json" do
  command "test 0"
  notifies :run, "ruby_block[dump node.json]", :before
  notifies :run, "execute[update_hostname]", :immediately
end

# make sure the hostname in CycleCloud is updated, so that the autoscaler can authorize us.
execute "update_hostname" do
  command "jetpack log 'updating hostname for '$(hostname) -p low"
  action :nothing
end

# this block prevents "bash[install_ocs_execd]" from running until the hostname is authorized
ruby_block "ocs exec #{node[:cyclecloud][:instance][:hostname]} authorized?" do
  block do
    # use . here as /bin/sh may not have source defined. (ubuntu)
    cmd =  Mixlib::ShellOut.new(
      ". /etc/profile.d/sgesettings.sh 2>> /tmp/authorized-hostname.log >> /tmp/authorized-hostname.log && qconf -se #{node[:cyclecloud][:instance][:hostname]} 2>> /tmp/authorized-hostname.log >> /tmp/authorized-hostname.log"
      ).run_command
      exit_code=cmd.exitstatus
    raise "ocs node #{node[:cyclecloud][:instance][:hostname]} not authorized yet. Exit code #{exit_code}" unless cmd.exitstatus == 0
  end
  retries 2
  retry_delay 30
  notifies :run, "bash[install_ocs_execd]", :delayed
end

# this starts the sge_execd process as well - also requires host to be authorized 
bash "install_ocs_execd" do
  code <<-EOF
  set -x
  if [ ! -e /etc/profile.d/sgesettings.sh ]; then
    echo Waiting for scheduler;
    exit 1;
  fi
  source /etc/profile.d/sgesettings.sh;
  which qconf > /dev/null || exit 1;
  qconf -se #{node[:cyclecloud][:instance][:hostname]} > /dev/null
  if [ $? != 0 ]; then
    echo #{node[:cyclecloud][:instance][:hostname]} is not authorized to join the cluster yet.
    exit 2
  fi

  cd $SGE_ROOT || exit 1;
  ./inst_sge -x -noremote -auto #{Chef::Config['file_cache_path']}/compnode.conf
  if [ $? == 0 ]; then
    touch /etc/ocsexecd.installed
    exit 0
  fi
  
  # install_file=$(ls -t #{ocsroot}/#{ocscell}/common/install_logs/*#{nodename_short}*.log | head -n 1)
  install_file=$(ls -t /tmp/install.* | grep -E 'install\.[0-9]+' | head -n 1)
  if [ ! -e $install_file ]; then
    echo There is no install log file 1>&2
    exit 1
  fi
  echo Here are the contents of $install_file 1>&2
  cat $install_file >&2
  exit 1
  EOF
  creates "/etc/ocsexecd.installed"
  action :nothing
  notifies :enable, "service[#{sge_execd_service}]", :immediately
  
end


# Is this pidfile_running check actually working? I see the file, but I don't see the debug logs
service sge_execd_service do
  action [:nothing]
end

