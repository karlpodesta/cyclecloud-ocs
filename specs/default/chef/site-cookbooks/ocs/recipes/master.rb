#
# Cookbook Name:: ocs
# Recipe:: master
#
# The SGE Master is a Q-Master and a Submitter
#

Chef::Log.warn("This recipe has been decprecated. Please use ocs::scheduler instead")
include_recipe "ocs::scheduler"

