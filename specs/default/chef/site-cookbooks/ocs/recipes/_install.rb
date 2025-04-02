#
# Cookbook Name:: ocs
# Recipe:: _install
#
# For installing GridEngine on master and compute nodes.
#

sgemake = node[:ocs][:make]     # ge, sge
sgever = node[:ocs][:version]   # 8.2.0-demo (ge), 8.2.1 (ge), 6_2u6 (sge), 2011.11 (sge, 8.1.8 (sge)
ocsroot = node[:ocs][:root] 
demoprefix = node[:ocs][:remote_prefix] 

# This is a hash for the ocs install files "sgebins"
# The default is the official release from Univa. These are named "bin-lx-amd64" and "common"
# The binaries from the old SGE distribution were named "64" and "common"
sgebins = { 'sge' => %w[64 common] }
sgebins.default = %w[bin-lx-amd64 common] 

sgeext = node[:ocs][:package_extension]

# Cycle's SGE packages end with the tgz extension
if node[:ocs][:make] == "sge"
  sgeext = "tgz"
end

sgebins[sgemake].each do |arch|
  if sgemake.start_with?("ge") && sgever.end_with?("demo") && node[:ocs][:use_external_download]
    directory node[:jetpack][:downloads] do 
      recursive true 
    end 

    remote_file "#{node[:jetpack][:downloads]}/#{sgemake}-#{sgever}-#{arch}.#{sgeext}" do
      source "#{Base64.decode64(demoprefix)}#{sgemake}-#{sgever}-#{arch}.#{sgeext}"
      action :create
    end
  else
    jetpack_download "#{sgemake}-#{sgever}-#{arch}.#{sgeext}" do
      project "ocs"
    end
  end
end

execute "untarcommon" do
  command "tar -xf #{node[:jetpack][:downloads]}/#{sgemake}-#{sgever}-common.#{sgeext} -C #{ocsroot}"
  creates "#{ocsroot}/inst_sge"
  action :run
end

sgebins[sgemake][0..-2].each do |myarch|

  execute "untar #{sgemake}-#{sgever}-#{myarch}.#{sgeext}" do
    command "tar -xf #{node[:jetpack][:downloads]}/#{sgemake}-#{sgever}-#{myarch}.#{sgeext} -C #{ocsroot}"
    case sgemake
    when "ge"
      #strip_bin essentially extracts "lx-amd64" from the filename.
      strip_bin = myarch.slice!(4..-1)
      creates "#{ocsroot}/bin/#{strip_bin}"
    when "sge"
      strip_bin = myarch.slice!(-3..-1)
      case strip_bin
      when "64"
        creates "#{ocsroot}/bin/linux-x64"
      when "32"
        creates "#{ocsroot}/bin/linux-x86"
      end
    end
    action :run
  end

end
