#
# Cookbook Name:: ocs
# Recipe:: sgemaster
#
# The SGE Master is a Q-Master and a Submitter 
#

Chef::Log.warn("This recipe has been decprecated. Please use ocs::master instead")
include_recipe "ocs::master"

