#
# Cookbook Name:: ocs
# Recipe:: sgeexec
#

Chef::Log.warn("This recipe has been decprecated. Please use ocs::execute instead")
include_recipe "ocs::execute"
