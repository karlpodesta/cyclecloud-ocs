name "sge_scheduler_role"
description "SGE Scheduler Role"
run_list("role[scheduler]",
  "recipe[cshared::directories]",
  "recipe[cuser]",
  "recipe[cshared::server]",
  "recipe[ocs::scheduler]")

default_attributes "cyclecloud" => { "discoverable" => true }
