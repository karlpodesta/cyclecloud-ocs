#
# Cookbook Name:: ocs
# Recipe:: scheduler
#
# The SGE Scheduler is a Scheduler and a Submitter
#

chefstate = node[:cyclecloud][:chefstate]

directory "#{node[:cyclecloud][:bootstrap]}/ocs"
directory "/opt/cycle/ocs"

slot_type = node[:ocs][:slot_type] || "scheduler"

myplatform=node[:platform_family]

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
  end
when 'rhel'
  # Install EPEL for jemalloc
  package 'epel-release'

  # jemalloc depends on EPEL
  package 'Install jemalloc' do
      package_name 'jemalloc'
  end
end


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


hostname = node[:cyclecloud][:instance][:hostname]
nodename = node[:cyclecloud][:instance][:hostname]
nodename_short = nodename.split(".")[0]

ocsroot = node[:ocs][:root]     # /sched/ge/ge-8.2.0-demo
ocscell = node[:ocs][:cell]

enable_selinux_file_permission_fixup_original = Chef::Config[:enable_selinux_file_permission_fixup]


ruby_block "set enable_selinux_file_permission_fixup to false" do
  block do
    Chef::Config[:enable_selinux_file_permission_fixup] = false
  end
end


directory ocsroot do
  owner node[:ocs][:user][:uid]
  group node[:ocs][:user][:gid]
  mode "0755"
  action :create
  recursive true
end

include_recipe "::_install"

directory File.join(ocsroot, 'conf') do
  owner node[:ocs][:user][:uid]
  group  node[:ocs][:user][:gid]
  mode "0755"
  action :create
  recursive true
end

template "#{ocsroot}/conf/#{nodename}.conf" do
  source "headnode.conf.erb"
  variables(
    :ocsroot => ocsroot,
    :nodename => nodename,
    :ignore_fqdn => node[:ocs][:ignore_fqdn],
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
  )
end

execute "installqm" do
  command "cd #{ocsroot} && ./inst_sge -m -auto ./conf/#{nodename}.conf"
  creates "#{ocsroot}/#{ocscell}"
  action :run
end

link "/etc/profile.d/sgesettings.sh" do
  to "#{ocsroot}/#{ocscell}/common/settings.sh"
end

link "/etc/profile.d/sgesettings.csh" do
  to "#{ocsroot}/#{ocscell}/common/settings.csh"
end

link "/etc/cluster-setup.sh" do
  to "#{ocsroot}/#{ocscell}/common/settings.sh"
end

link "/etc/cluster-setup.csh" do
  to "#{ocsroot}/#{ocscell}/common/settings.csh"
end


sgemaster_path="#{ocsroot}/#{ocscell}/common/sgemaster"
sgeexecd_path="#{ocsroot}/#{ocscell}/common/sgeexecd"

execute "set qmaster hostname" do
  if node[:platform_family] == "rhel" && node[:platform_version] < "7" then
    command "echo #{node[:hostname]} > #{ocsroot}/#{ocscell}/common/act_qmaster"
  else
    command "hostname -f > #{ocsroot}/#{ocscell}/common/act_qmaster"
  end
end

case node[:platform_family]
when "rhel"
  mail_root = "/bin"
when "debian"
  mail_root = "/usr/bin"
else
  throw "cluster_init: unsupported platform"
end

template "#{ocsroot}/conf/global" do
  source "global.erb"
  owner "root"
  group "root"
  mode "0755"
  variables(
    :ocsroot => ocsroot,
    :mail_root => mail_root
  )
end

template "#{ocsroot}/conf/sched" do
  source "sched.erb"
  owner "root"
  group "root"
  mode "0755"
end

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

# Remove any hosts from previous runs
bash "clear old hosts" do
  code <<-EOH
  for HOST in `ls -1 #{ocsroot}/#{ocscell}/spool/ | grep -v qmaster`; do
    . /etc/cluster-setup.sh
    qmod -d *@${HOST}
    qconf -dattr hostgroup hostlist ${HOST} @allhosts
    qconf -de ${HOST}
    qconf -ds ${HOST}
    qconf -dh ${HOST}
    rm -rf #{ocsroot}/#{ocscell}/spool/${HOST};
  done && touch #{chefstate}/ocs.clear.hosts
  EOH
  creates "#{chefstate}/ocs.clear.hosts"
  action :run
end

service sge_execd_service do
  action [:enable]
end

execute "stop non-daemon qmaster" do
  command "#{ocsroot}/#{ocscell}/common/sgemaster stop"
  only_if "ps aux | grep sge_qmaster | grep -v grep | grep -q qmaster"
end

service sge_qmasterd_service do
  action [:enable, :start]
end

execute "setglobal" do
  command ". /etc/cluster-setup.sh && qconf -Mconf #{ocsroot}/conf/global && touch #{chefstate}/ocs.global.set"
  creates "#{chefstate}/ocs.global.set"
  action :run
end

execute "setsched" do
  command ". /etc/cluster-setup.sh && qconf -Msconf #{ocsroot}/conf/sched && touch #{chefstate}/ocs.sched.set"
  creates "#{chefstate}/ocs.sched.set"
  action :run
end

execute "showalljobs" do
  command "echo \"-u *\" > #{ocsroot}/#{ocscell}/common/sge_qstat"
  creates "#{ocsroot}/#{ocscell}/common/sge_qstat"
  action :run
end

bash "schedexecinst" do
  code <<-EOF
  
  cd #{ocsroot} || exit 1;
  ./inst_sge -x -noremote -auto #{ocsroot}/conf/#{nodename}.conf
  if [ $? == 0 ]; then
    touch #{chefstate}/ocs.sgesched.schedexecinst
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
  creates "#{chefstate}/ocs.sgesched.schedexecinst"
  action :run
end

template "#{ocsroot}/conf/exec" do
  source "exec.erb"
  owner "root"
  group "root"
  mode "0755"
  variables(
    :hostname => hostname,
    :slot_type => slot_type,
    :placement_group => "default"
  )
end

template "#{ocsroot}/conf/ocs.q" do
  source "ocs.q.erb"
  owner "root"
  group "root"
  mode "0755"
  variables(
    :ocsroot => ocsroot,
    :scheduler => hostname
  )
end

remote_directory "#{ocsroot}/hooks" do
  source 'hooks'
  owner 'root'
  group 'root'
  mode '0755'
  action :create
end


cookbook_file "#{ocsroot}/SGESuspend.sh" do
  source "sbin/SGESuspend.sh"
  owner "root"
  group "root"
  mode "0755"
  only_if "test -d #{ocsroot}"
end

cookbook_file "#{ocsroot}/SGETerm.sh" do
  source "sbin/SGETerm.sh"
  owner "root"
  group "root"
  mode "0755"
  only_if "test -d #{ocsroot}"
end


if node[:ocs][:make]=='ge'
# UGE can change complexes between releases
  if node[:ocs][:version] >= "8.5"
  
    %w( slot_type onsched placement_group exclusive nodearray ).each do |confFile|
      cookbook_file "#{ocsroot}/conf/complex_#{confFile}" do
        source "conf/complex_#{confFile}"
        owner "root"
        group "root"
        mode "0755"
        only_if "test -d #{ocsroot}/conf"
      end

      execute "set #{confFile} complex" do
        command ". /etc/cluster-setup.sh && qconf -Ace #{ocsroot}/conf/complex_#{confFile} && touch #{chefstate}/ocs.setcomplex.#{confFile}.done"
        creates "#{chefstate}/ocs.setcomplex.#{confFile}.done"
        action :run
      end
    end
  else
    bash "install complexes" do
      code <<-EOH
      . /etc/cluster-setup.sh 
      qconf -sc 2>&1| grep -vE '^slot_type|^onsched|^placement_group|^exclusive|^nodearray' > #{ocsroot}/conf/complexes_install || exit 1;
      cat >> #{ocsroot}/conf/complexes_install <<EOF
nodearray               nodearray     RESTRING    ==      YES         NO         NONE     0       NO
slot_type               slot_type     RESTRING    ==      YES         NO         NONE     0       NO
exclusive               exclusive     BOOL        EXCL    YES         YES        0        1000    NO
placement_group         group         RESTRING    ==      YES         NO         NONE     0       NO
onsched                 os            BOOL        ==      YES         NO         0        0       NO
EOF
      qconf -Mc #{ocsroot}/conf/complexes_install || test 1
      qconf -sc | grep -q slot_type || exit 1
      qconf -sc | grep -q onsched || exit 1
      qconf -sc | grep -q placement_group || exit 1
      qconf -sc | grep -q exclusive || exit 1
      qconf -sc | grep -q nodearray || exit 1
      EOH
    end
  end
elsif node[:ocs][:make]=='sge'

  # OGS does't have qconf -Ace options 
  complex_file = "conf/complexes"

  cookbook_file "#{ocsroot}/conf/complexes" do
    source complex_file
    owner "root"
    group "root"
    mode "0755"
    action :create
  end

  execute "set complexes" do
    command ". /etc/cluster-setup.sh && qconf -Mc #{ocsroot}/conf/complexes && touch #{chefstate}/ocs.setcomplexes.done"
    creates "#{chefstate}/ocs.setcomplexes.done"
    action :run
  end
end

pe_list = [ "make", "mpi", "mpislots", "smpslots"]

file "#{ocsroot}/conf/pecfg" do
  content <<-EOF
pe_list [@cyclehtc=make,smpslots],[@cyclempi=mpi,mpislots]
hostlist @cyclehtc,@cyclempi
EOF
  mode "0755"
end

pe_list.each do |confFile|

  template "#{ocsroot}/conf/#{confFile}" do
    source "#{confFile}.erb"
    owner "root"
    group "root"
    mode "0755"
    variables(
      :ocsroot => ocsroot
    )
  end 

  execute "Add the conf file: " + confFile do
    command ". /etc/cluster-setup.sh && qconf -Ap #{File.join(ocsroot, 'conf', confFile)}"
    not_if ". /etc/cluster-setup.sh && qconf -spl | grep #{confFile}"
  end
end

bash "add @cyclempi hostgroup" do
  code <<-EOH
  . /etc/cluster-setup.sh
  set -e
  cat > $SGE_ROOT/conf/cyclempi <<EOF
group_name @cyclempi
hostlist #{hostname}
EOF
  qconf -Ahgrp $SGE_ROOT/conf/cyclempi
EOH
  not_if ". /etc/cluster-setup.sh && qconf -shgrpl | egrep -q '^@cyclempi$'"
end

bash "add @cyclehtc hostgroup" do
code <<-EOH
  set -e
  . /etc/cluster-setup.sh
  cat > $SGE_ROOT/conf/cyclehtc <<EOF
group_name @cyclehtc
hostlist #{hostname}
EOF
  qconf -Ahgrp $SGE_ROOT/conf/cyclehtc
EOH
  not_if ". /etc/cluster-setup.sh && qconf -shgrpl | egrep -q '^@cyclehtc$'"
end

# Don't set the parallel environments for the all.q once we've already run this.
# To test, look for one of the PEs we add in the list of PEs associated with the queue.
execute "setpecfg" do
  command ". /etc/cluster-setup.sh && qconf -Rattr queue #{ocsroot}/conf/pecfg all.q"
  not_if ". /etc/cluster-setup.sh && qconf -sq all.q | grep mpislots"
end

# Configure the qmaster to not run jobs unless the jobs themselves are configured to run on the qmaster host.
# It shouldn't be a problem for this to be set every converge.
execute "setexec" do
  command ". /etc/cluster-setup.sh && qconf -Me #{ocsroot}/conf/exec"
end

#
execute "ocs.qcfg" do
  command ". /etc/cluster-setup.sh && qconf -Rattr queue #{ocsroot}/conf/ocs.q all.q && touch #{chefstate}/ocs.qcfg"
  only_if "test -f #{ocsroot}/SGESuspend.sh && test -f #{ocsroot}/SGETerm.sh && test -f #{ocsroot}/conf/ocs.q && test ! -f #{chefstate}/ocs.qcfg"
end

# Pull in the Jetpack LWRP
include_recipe 'jetpack'

monitoring_config = "#{node['cyclecloud']['home']}/config/service.d/ocs.json"
file monitoring_config do
  content <<-EOH
  {
    "system": "ocs",
    "cluster_name": "#{node[:cyclecloud][:cluster][:name]}",
    "hostname": "#{node[:cyclecloud][:instance][:public_hostname]}",
    "ports": {"ssh": 22},
    "cellname": "#{ocscell}",
    "ocsroot": "#{node[:ocs][:root]}"
  }
  EOH
  mode 750
  not_if { ::File.exist?(monitoring_config) }
  only_if { node[:cyclecloud][:jetpack][:version] < "8.1" }
end

jetpack_send "Registering QMaster for monitoring." do
  file monitoring_config
  routing_key "#{node[:cyclecloud][:service_status][:routing_key]}.ocs"
  only_if { node[:cyclecloud][:jetpack][:version] < "8.1" }
end


relevant_complexes = node[:ocs][:relevant_complexes] || ["slots", "slot_type", "nodearray", "m_mem_free", "exclusive"]
relevant_complexes_str = relevant_complexes.join(",")

cookbook_file "/opt/cycle/ocs/logging.conf" do
  source "conf/logging.conf"
  owner 'root'
  group 'root'
  mode '0644'
  action :create
  not_if {::File.exist?("#{node[:cyclecloud][:bootstrap]}/ocs/logging.conf")}
end


ruby_block "restore enable_selinux_file_permission_fixup default" do
  block do
    Chef::Config[:enable_selinux_file_permission_fixup] = enable_selinux_file_permission_fixup_original
  end
end


bash 'setup cyclecloud-ocs' do
  code <<-EOH
  set -e
  set -x
  . /etc/cluster-setup.sh
  cd #{node[:cyclecloud][:bootstrap]}/

  rm -f #{node[:ocs][:installer]} 2> /dev/null

  jetpack download #{node[:ocs][:installer]} --project ocs ./
   
  tar xzf #{node[:ocs][:installer]}

  cd cyclecloud-ocs/
  
  INSTALLDIR=/opt/cycle/ocs
  mkdir -p $INSTALLDIR/venv
  ./install.sh --install-python3 --venv $INSTALLDIR/venv
  ./generate_autoscale_json.sh --cluster-name #{node[:cyclecloud][:cluster][:name]} \
                               --username     #{node[:cyclecloud][:config][:username]} \
                               --password     #{node[:cyclecloud][:config][:password]} \
                               --url          #{node[:cyclecloud][:config][:web_server]} \
                               --relevant-complexes #{relevant_complexes_str} \
                               --idle-timeout #{node[:ocs][:idle_timeout]}

  touch #{node[:cyclecloud][:bootstrap]}/ocsvenv.installed
  EOH
  action :run
  not_if {::File.exist?("#{node[:cyclecloud][:bootstrap]}/ocsvenv.installed")}
end
