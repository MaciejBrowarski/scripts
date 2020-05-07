#!/usr/bin/perl -w
#
# VERSION 2.5
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
# 2.4 1013 Nov - use named pipe  in /tmp/ perl-main-<user>
# 2.5 2014 January - add nprobes parameters (default now is 2 for www change just), ask_pref_ids (prefered IDS to monitor) ids_check (script support for alarms)
# 2.6 2014 September - add version command
#
# Copyright: 2009 - 2014 by BROWARSKI
#

use lib "/home/$ARGV[1]/get/scripts";
use Net::SNMP  qw(:snmp);
use strict;
use common_cmit;

# our $debug = 1;
#
# for each period we should repeat asking about service in 1 minute when prevoius asking was bad
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

#
# timeout for when one or more IDS are unavailable
# require by get_www
#
our $timeout_ids = 2;
#
# configuration directory in IDS
#
our $cfg_dir = "cfg";
#
# time, between we should check serwis
# if current time and time taken from log file with good flag are less below variable
# no futher action is taken
# TODO: check is below is used (shouldn't be now)
#
# our $good_time = 2 * 60 + 10;

our $dir = "$ENV{HOME}/get";

our ($www, $mon_port, $ping, $login, $dns, $external, $protocol, $snmp);
our ($cl, $configf, $start_minute, $hostname, $host_id);
our ($www_api);

our $script_duration = 30;

$configf = "main";

my $version = "0";
#
# argv: 0 - hostname, 1 - user
#
if ($ARGV[0]) {
	$hostname = $ARGV[0];
} else {
	print "provide hostname\n";
	exit 1;
}
if ($hostname =~ /(\d{2})$/) {
	$host_id = $1;
} else {
	print "hostname doesn't end with 2 digit\n";
}

my $pipe_main = "/tmp/perl-main-";
my $pipe_ver = "/tmp/perl-version-";
if ($ARGV[1]) {
        $dir = "/home/".$ARGV[1];
	chomp($dir);
	$dir .= "/get/";
	$pipe_main .= $ARGV[1];
	$pipe_ver .= $ARGV[1];
	chomp($pipe_main);
	chomp ($pipe_ver);
} else {
	print "provide user\n";
	exit 1;
}
#
# get version from file
# this is important, as we like to know which version is 
# currenlty running (is this from disks, or any old one)
#
if (open FILE, "/home/$ARGV[1]/get/scripts/version") {
	$version = <FILE>;
	close FILE;
} else {
	print "No version file for scripts\n";
	exit 1;
}
chomp $hostname;

$SIG{CHLD} = 'IGNORE';

#
# MAIN LOOP
#
(-p $pipe_main) or create_pipe($pipe_main);

my $f = fork();
if ($f < 0) {
	$env::debug and wlog "MAIN: can't fork:$!\n";
}
#
# parent
#
if ($f) {
	my $f_n = "/home/$ARGV[1]/get/pid/main_perl.pid";
	if (open PLIK, "> ".$f_n) {
	print PLIK "$f\n";
	close PLIK;
	} else {
		$env::debug and wlog "MAIN: unable to write pid file $f_n: $!\n";
	}
	exit (0);
}
# open(STDIN,  "< /dev/null");
# open(STDOUT, "> /dev/null");
setsid();

my $pipe =  reopen_pipe($pipe_main);

for (;;) {
	 my $script;
        my $user;
        my $monitor;
	my $rline;

	my $rc = sysread $pipe, $rline, 4096;
	if ($rc == 0) {
		$env::debug and wlog "MAIN: received rc 0: $!\n";
		close ($pipe) or wlog "unable to close pipe:$!\n";
		$pipe =  reopen_pipe($pipe_main);

		next;
	}
	if ($rc < 0) {
		$env::debug and wlog "MAIN: sysread received rc $rc: $!\n";
		close ($pipe) or wlog "unable to close pipe:$!\n";
		 $pipe =  reopen_pipe($pipe_main);
		next;
	}
	my @lines = split /\n/, $rline;

	foreach my $line (@lines) {
		$ask_pref_ids = 0;
		$ids_check = 0;
		$main::nprobes = 2;
		chomp ($line);

		#
		# for internal logging
		# this variable is overwriten each loop by initial
		#
		$configf = "main";
		my $ct = time();
		my $atime = 0;
		#
		# if ask about running version
		#
		if ($line =~ m|<version>|)  {
			if (open FILE, ">$pipe_ver") {
				print FILE $version;
				close FILE;
			}
		}

		if ($line =~ m|<script:([\d\w\_]+)/>|) {
			my $pr = $1;
			$script = $pr.".pl";
			#
			# check is prefix for prefernece IDS
			#
			if ($pr =~ /([\d\w]+)_pref$/) { 
				$script = $1.".pl"; 
				$ask_pref_ids = $host_id;
			}
			#
			# check is prefix for IDS check
			# which should be start for check IDS
			# so nprobes should be 1
			# id_check mean that we omit 
			# prefered IDS and check all monitors prefered and not-prefered
			#
			if ($pr =~ /([\d\w]+)_check$/) { 
				$script = $1.".pl"; 
				$ids_check = 1;
				$nprobes = 1;
			}
		}
		($line =~ m|<atime:(\d+)/>|) and $atime = $1;
		($line =~ m|<user:([\w\.\-\_\d]+)/>|) and $user = $1;
		($line =~ m|<monitor:([\w\.\-\_\d\ ]+)/>|) and $monitor = $1;

		if (! $script) {
			$env::debug and wlog "LOOP: no script found: '".$line."'\n";
			next;
		}
		if (($ct - 2) > $atime) {
			$env::debug and wlog "LOOP: time passed, not allowed\n";
			next;
		}
		my $pid = fork();
		if ($pid < 0) {
			$env::debug and wlog "LOOP: fork error: $!\n";
			next;
		}
		#
		# parent
		# just log about child
		# and back to read pipe
		#
		if ($pid) {
			$env::debug and wlog "LOOP: created $pid for $line\n";
			next;
		}
		#
		# child
		#
		close ($pipe) or wlog "unable to close pipe:$!\n";
		$main::www_api = 0;
		if ($line =~ m|<www/>|) { 
			$main::nprobes = 1;
			$main::www_api = 1;
		}

		$SIG{CHLD} = "DEFAULT";
		my ($p_name, $passwd, $uid, $gid, $p_quota,$p_comment, $gcos, $p_dir, $shell) = getpwnam($ARGV[1]);
		# my $uid = (getpwnam($ARGV[1]))[2];
	
		if (! initial($dir."/scripts/".$script)) {
		 	$env::debug and wlog "unable to initial variables\n";
			exit (0);
		}
		if (($main::ping) || ($main::troute)) {
	                $env::debug and wlog "child: script $script with root privileges\n";
	        } else {
			if ($gid) {
				setgid($gid) or wlog "unable setgid: $!\n";
			}
	                if ($uid) {
			 	setuid($uid) or wlog "unable setuid: $!\n";
			}
			#
			# this log will create new log file, so need to be with new UID
			#
			$env::debug and wlog "child: switch to UID: $uid\n";
	        }
	
		#
		# if there is all paremeters required then jump into proper function
		# <hostname> 1:<user> 2:<monitor name to run>
		#
		if ($monitor) {
			user_one_action($user, $monitor);
		#
		# MAIN FUNCTION
		#
		} else {
			user_loop ();
		}
		exit(0);
	}
}
