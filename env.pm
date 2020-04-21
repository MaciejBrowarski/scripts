# env variables
#
# 0.1 - created
# 1.0 2017 February - add good time as env variable
# 1.1 2018 January - add debug as env variable
#
# Created by BROWARSKI
#
package env;

our $faddr = "http://www.cmit.net.pl/USERENV/";
our $faddr_local = "/home/USERENV/get/www/";
our $user = "USERENV";

#
# debug
# 0 - no log
# 1 - log in log/ folder
# 2 - log into log/folder + on screen
#
our $debug = 0;

#
# time, between we should check service
# if current time and time taken from log file with good flag are less below variable
# no futher action is taken
#
our $good_time = 45;

return 1;

