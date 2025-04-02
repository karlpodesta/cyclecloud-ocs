default[:ocs][:make] = "sge"
default[:ocs][:version] = "2011.11"
default[:ocs][:root] = "/sched/sge/sge-2011.11"
default[:ocs][:cell] = "default"
default[:ocs][:package_extension] = "tar.gz"
default[:ocs][:installer] = "cyclecloud-ocs-pkg-2.0.20.tar.gz"
default[:ocs][:use_external_download] = false
default[:ocs][:remote_prefix] = nil

default[:ocs][:sge_qmaster_port] = "537"
default[:ocs][:sge_execd_port] = "538"
default[:ocs][:sge_cluster_name] = "grid1"
default[:ocs][:gid_range] = "20000-20100"
default[:ocs][:qmaster_spool_dir] = "#{node['ocs']['root']}/#{node['ocs']['cell']}/spool/qmaster" 
default[:ocs][:execd_spool_dir] = "#{node['ocs']['root']}/#{node['ocs']['cell']}/spool"
default[:ocs][:spooling_method] = "berkeleydb"

default[:ocs][:shadow_host] = ""
default[:ocs][:admin_mail] = ""

default[:ocs][:idle_timeout] = 300

default[:ocs][:managed_fs] = true
default[:ocs][:shared][:bin] = true
default[:ocs][:shared][:spool] = true

default[:ocs][:slots] = nil
default[:ocs][:slot_type] = nil


default[:ocs][:is_grouped] = false

default[:ocs][:ignore_fqdn] = true

# Grid engine user settings
default[:ocs][:group][:name] = "sgeadmin"
default[:ocs][:group][:gid] = 536

default[:ocs][:user][:name] = "sgeadmin"
default[:ocs][:user][:description] = "SGE admin user"
default[:ocs][:user][:home] = "/shared/home/sgeadmin"
default[:ocs][:user][:shell] = "/bin/bash"
default[:ocs][:user][:uid] = 536
default[:ocs][:user][:gid] = node[:ocs][:group][:gid]

default[:ocs][:max_group_backlog] = 1
