#
# Cookbook Name:: ocs
# Recipe:: sgefs
#
# Sets up the filesystem for $SGE_ROOT on non-master
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

sgeroot = node[:ocs][:root]
sgeroot_parts = sgeroot.split(File::SEPARATOR)
sched_mnt = node[:cshared][:client][:defaults][:sched][:mountpoint]
sched_mnt_parts = sched_mnt.split(File::SEPARATOR)

# /sched is hardcoded in cshared. search for it, strip it out sgeroot.
remote_sgeroot = sgeroot.gsub("/sched",sched_mnt)

shared_bin = node[:ocs][:shared][:bin]
shared_spool = node[:ocs][:shared][:spool]


# choose whether to mount at base, or do selective links.
sge_root_overlaps_mnt = sgeroot_parts[1] == sched_mnt_parts[1]

if sge_root_overlaps_mnt # selective mounting not possible, mount to sge_root

  log 'Gridengine overlap' do
    message 'ocs nfs mounted at sge_root'
    level :info
  end

  if not(shared_spool)
    Chef::Log.warn("ocs.root and cshared.client.defaults.sched.mountpoint coincide, ignoring ocs.shared.spool = false")
  end
  if not(shared_bin)
    Chef::Log.warn("ocs.root and cshared.client.defaults.sched.mountpoint coincide, ignoring ocs.shared.bin = false")
  end

else # not overlapping, link from sge-root to sge-mount

  if shared_bin and shared_spool # all shared, link root dirs

    log 'message' do
      message 'Gridengine Shared All, linking at base '
      level :info
    end

    link sgeroot_parts[0..1].join(File::SEPARATOR) do
        to sched_mnt_parts[0..1].join(File::SEPARATOR)
    end

  else # selecive links
    
    log 'message' do
      message 'Gridengine selectively link shared dirs in sge_root'
      level :info
    end

    %w( conf default ).each do |dir|
      directory "#{sgeroot}/#{dir}" do
        owner node[:ocs][:user][:name]
        group node[:ocs][:group][:name]
        mode "0755"
        recursive true
      end
    end 
 
    log 'message' do
      message 'Gridengine shared config, linking config to shared'
      level :info
    end  

    %w( default/common util host_tokens ).each do |dir|
      link "#{sgeroot}/#{dir}" do
        to "#{remote_sgeroot}/#{dir}"
      end
    end

    %w( install_execd install_qmaster inst_sge SGESuspend.sh SGETerm.sh ).each do |script|
      link "#{sgeroot}/#{script}" do
        to "#{remote_sgeroot}/#{script}"
      end
    end

    if shared_bin # meaning #not shared_
      
      log 'message' do
        message 'Gridengine shared binaries, linking binaries to shared'
        level :info
      end  

      link "#{sgeroot}/bin" do
        to "#{remote_sgeroot}/bin"
      end

      link "#{sgeroot}/utilbin" do
        to "#{remote_sgeroot}/utilbin"
      end

      directory "#{sgeroot}/default/spool" do
        owner node[:ocs][:user][:name]
        group node[:ocs][:group][:name]
        mode "0755"
        recursive true
      end

    elsif shared_spool

      log 'message' do
        message 'Gridengine shared spool, linking spool to shared'
        level :info
      end  

      link "#{sgeroot}/default/spool" do
        to "#{remote_sgeroot}/default/spool"
      end
    
    end
  end
end


link "/etc/profile.d/sgesettings.sh" do
  to "#{sgeroot}/default/common/settings.sh"
end

link "/etc/profile.d/sgesettings.csh" do
  to "#{sgeroot}/default/common/settings.csh"
end

link "/etc/cluster-setup.sh" do
  to "#{sgeroot}/default/common/settings.sh"
end

link "/etc/cluster-setup.csh" do
  to "#{sgeroot}/default/common/settings.csh"
end
