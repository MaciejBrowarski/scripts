#!/usr/bin/perl -w
#
# VERSION 3.2
#
# HISTORY
# 0.0.1 - May 2009 - First production
# 0.0.2 November 2009 - fit to netbone
# 0.0.3 December - more verbose on debug
# 0.0.5 2010 January - common script for all things
# 0.0.6 2010 Fabruary - HiRes  for port and ping and www
# 0.0.7 2010 February - rewrite for common functions
# 0.0.8 2010 March - rewrite get_file for optimalisation
#                       - add ARGV[0] parameter as name node
# 0.0.9 2010 March - add sms_send and posibilty to send sms in case of alarm
# 0.0.10 2010 April - correct get_www, that gethostbyname will write information to file
#                       - add ARGV[1] parameter as user
#                       - add ARGV[2] parameter as name of action (need for ad hoc request)
# 0.0.11 2010 May - divide to common library and dedicated scripts (for port and ping)
# 0.0.12 2010 June - change alarm_time from constant variable to variable taken from configuration file
# 0.1.0 2010 July - fit to new version
# 0.1.1 2010 Septmeber - account with prefix . (dot) are not taken under default launch, they must be taken directly
# 0.1.2 2011 February - add login method (pop3/ftp)
# 0.1.3 2011 March - add get_www_v2 to implement http and https protocol
# 0.1.4 2011 April - add DNS monitor
# 0.1.5 2011 May - add www prefix for http and https monitors
# 0.1.6 2011 May - create get_ping_v2 for more hosts 
# 0.1.7 2011 June - add external script
# 0.1.8 2012 October - add response time to www, ping and port
# 0.2.0 2013 February - update for xml cfg files (rewrite MAIN LOOP and get_ping_v2)
# 0.2.1 2013 July - add monitor ID and write daily stat to file with monitor_id names
# 0.2.2 2013 Oct - add check_pass_ to delete alarm file when all is good after alarm_iff
# 2.3 2013 Nov - make funtions for flow and copy them to common_cmit
# 2.4 2014 Jan - add pref_ids variable
# 3.0 2017 Feb - add troute monitor
# 3.1 2017 Nov - add poczta monitor
# 3.2 2018 Jan - move debug variable to env.pm file
#
# Copyright: 2009 - 2018 by BROWARSKI
#
use FindBin qw($Bin);
use lib "$Bin";
# use lib "$ENV{HOME}/get/scripts";

use strict;
use Time::HiRes();
use common_cmit;

# our $debug = 1;
#
# for each period we should repeat asking about servis in 1 minute when prevoius asking was bad
#
our $timeout = 10;
#
# in case of failure, how many times repeat, for this monitor, monitor ask
#
our $nprobes = 2;
#
# prefered IDS to run
#
our $ask_pref_ids = 0;
#
# is this ask for monitor support (second in >30s )
#
our $ids_check = 0;

our $www_api = 0;
#
# timeout for when one or more IDS are unavailable
# require by get_www
#
our $timeout_ids = 2;
#
# configuration directory in IDS
#
our $cfg_dir = "cfg";

our $dir = "$ENV{HOME}/get";

our $start_minute;
our $script_duration = 30;


our ($hostname, $host_id);
if ($ARGV[0]) {
	$hostname = $ARGV[0];
} else {
	$hostname = `/bin/hostname`;
	$env::debug and wlog "MAIN: no hostname provided as ARGV[0], use $hostname\n";
}
chomp $hostname;

if ($hostname =~ /(\d{2})$/) {
        $host_id = $1;
} else {
        print "hostname doesn't end with 2 digit\n";
}


our ($www, $mon_port, $ping, $login, $dns, $external, $protocol, $troute, $poczta);
our ($cl, $configf);

my $exec_name = $0;
print "DEBUG: $exec_name\n";

if ($exec_name =~ /([\d\w]+)_pref\.pl$/) {
	$exec_name =~ s/_pref//;
	$ask_pref_ids = $host_id;
}
if ($exec_name =~ /([\d\w]+)_check\.pl$/) {
	$exec_name =~ s/_check//;
        $ids_check = 1;
}

print "DEBUG #1: $exec_name\n";

initial($exec_name) or die "unable to initial variables\n";
#
# if there is all paremeters required then jump into proper function
# <hostname> 1:<user> 2:<monitor name to run>
#
if ($ARGV[2]) {
	user_one_action($ARGV[1], $ARGV[2]);
#
# MAIN FUNCTION
#
} else {
	user_loop ();
}
