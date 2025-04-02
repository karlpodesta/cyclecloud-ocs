name             "ocs"
maintainer       "Cycle Computing"
maintainer_email "cyclecloud-support@cyclecomputing.com"
license          "Apache 2.0"
description      "Installs/Configures ocs"
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          "2.0.20"

%w{ cuser cycle_server cshared cyclecloud }.each {|c| depends c }
