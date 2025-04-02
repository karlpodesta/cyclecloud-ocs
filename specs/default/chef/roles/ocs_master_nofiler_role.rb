name "sge_master_nofiler_role"
description "SGE Master, but not the NFS server"
run_list("role[scheduler]",
  "recipe[cshared::client]",
  "recipe[cuser]",
  "recipe[ocs::master]")

default_attributes "cyclecloud" => { "discoverable" => true }
