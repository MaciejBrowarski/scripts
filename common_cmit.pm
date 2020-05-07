#!/usr/bin/perl -w
#
# Common function for monitors
#
# Version: 3.2
#
# History:
# 0.0.1 2010 May -  Created
# 0.0.2 2010 May - add multiple SMS numbers
# 0.0.3 2010 May - add internal mail client
# 0.0.4 2010 May - fit for snmp_* clients - add snmp_get
# 0.0.5 2010 June - variable control (for $rest)
# 0.1.0 2010 July - snmp_get - first return parameter as success/failure flag
#	2010 August - get_file_name created for flexible and add monitor type
# 0.1.1 2011 January - add for wlog debug > 1 print to stdout too
#	2011 January - add month array
# 0.1.2 2011 February - add HTTPS support in get_www
# 0.1.3 2011 March - add webservice as channel to send alarms
# 0.1.4 2011 April - add check_file_v2, which will return with success or fail status and time when status is started
# 0.1.5 2011 April - add send_info function as new version of send_alarm (which become  obsolute)
# 0.1.6 2011 June - create send_http and rewrite sms_send, fix send_webservice for return value
# 0.1.7 2011 July - clean up: delete send_alarm (send_info is new), get_info (get_info_v2 is new) , add USED BY in comments
#	2011 July - rewrite send_info that each alarm is send parralel (fork'ed)
# 0.1.8 2011 July - rewrite sms_send and send_http for MultiInfo SMS method (add Curl::Easy for ssl key support)
# 0.1.9 2011 July - add ids_data_get for more detailed works with IDS (fork, pipe, exec)
# 0.1.10 2011 October - add http notification
# 0.1.12 2012 July - rewrite send_http to use inter https_cat instead get_https (less prone of errors)
# 0.1.13 2012 August - use external SMS program to send e-mails
# 0.1.14 2012 September - rewrite send_info to support other languages (english)
# 0.1.15 2012 October - add send_http_v2 to accept dedicated time_out
# 0.1.16 2013 May - rewrite send_info for group alarm
# 0.1.17 2013 June - rewrite send_info to accept groups
# 0.1.18 2013 July - create check_file_v3 to accept monitor_id
# 0.1.19 2013 July - add decode_monitor_id function
# 2.0 	2013 Aug - add common function for agent and snmp ( get_monitor_grow and get_monitor_linear)
# 2.1 	2013 Aug - add to send_info addtional entry for history alarm
# 2.2 	2013 Sep - add mail from as alarm@ in send_info function
#		 - fix send_mail function that status of QUIT command isn't take as result of send whole e-mail (important is ret code 384 after DATA)
# 2.3 	2013 October - extract from send_info check_pass_time fuction 
# 2.4	2013 November - optimise for speed up (remove unused functions: send_sms, get_http) and start to use require for module instead of use
# 2.5 	2014 January - clean up (delete unused functions: check_file_v2)
# 2.6	2014 January - add check_time_slot function, pref_ids variable and functionality
# 2.7 	2014 February - review send_http_v2 and get_www_v2 for error code 301 & 302
# 2.8 	2014 March - correct get_monitor_ with good time
# 2.9 	2014 March - add Date to e-mail header
# 2.10 	2014 April - add freeze to send_info
# 2.11 	2014 April - add send_http_v3 for POST data
# 2.12	2014 May - add send_http_v4 with cookie support
# 2.13	2014 May - add Message-ID to e-mail header
# 2.13.1 2015 Sep - fix get_monitor_grow with interface delimeter
# 2.14 2016 Jan - add SMTPS method to send e-mail (on 465 port) - update conv_v2 for write buffer control
# 2.15 2017 January - move sms text conversion  (from non-alpha to %<hex>) to sms program
# 2.16 2017 February - add good time as env variable
# 3.0 2017 February - add troute monitor
# 3.0.1 2017 February - minor fix for troute
# 3.1 2017 November - add poczta
# 3.2 2017 December - fix get_file (first get tail of log, if less data, then gett current day, if still not enough then previuos file)
# 3.3 2018 January - rewrite debug variable to env cfg file
#
# Copyright by BROWARSKI
#
use strict; 
use POSIX qw(setuid setgid setsid mkfifo);
use Fcntl;
use language;
use Time::HiRes;
use Net::DNS;
use Net::Ping;
use Net::SNMP  qw(:snmp);
use IO::Socket::SSL;
# $IO::Socket::SSL::DEBUG=0;
use Socket;
use env;

my $SSL_trace = 0;
#
# default e-mail address (can be overwitten by alarm)
#
our $mail_from = "biuro\@cmit.net.pl";

our $sms_cl = "$ENV{HOME}/get/sms/bin/sms";
our $sms_path = "$ENV{HOME}/get/sms/cfg/";

#
# name: wlog
# desc: write log into file with timestamp
#
# global variables
# configf - what kind of log
# debug = 2 write into output too
#
# in:
# 1 - log string
#
# USED BY:
# ALL :)
#
sub wlog {
	my $out = shift;

	my $t = time;
	my $dat = localtime($t);
	($env::debug > 1) and print "$$-$dat: $out"; 

	if (open ERR, ">>".$main::dir."/log/$t-".$main::configf."-$$.log")   {
		print ERR "$dat: $out";
		close ERR;
	}
};
# name: blad
# desc:critcal error
# in:
# out:
# no 
# USED BY:
# hope, no one using this :)
#
sub blad {
	my $str = shift;
	wlog ($str);
	exit 1;
}
#
# language of comments per account
# (default  is english)
#
our $lang = \%language::english;
our $language = "english";

sub set_language {
    my $user = shift;
    my ($jest, @lan) = ids_data_get ("get", "$user/language");
    if ($jest > 0) {
        if ($lan[0] == 0) { $lang = \%language::polski; $language = "polski";}
        if ($lan[0] == 1) { $lang = \%language::english; $language = "english"; }
    }
    $env::debug and wlog "set_language: lang set to: $language\n";
}
#
# function should be running after each external monitoring
# function check is script is still in defined time slot
# if time passed of running, script should immediate shutdown
# IN:
# NONE
#
# OUT:
# 0 - still in our time lot
# 1 - exit immediate
#
sub check_time_slot()
{
	#
	# round current time (simple floor)
	#
	my $current_minute = int(time / $main::script_duration) * $main::script_duration;
        if ($current_minute > $main::start_minute) {
	        $env::debug and wlog "check_time_slot: Current time $current_minute greater that start time $main::start_minute plus $main::script_duration s . Exiting...\n";
                        return 1;
        }
	return 0;
}
#
# NAME: decode_monitor_id
# DESC: decode monitor ID paramter and return what for is it (ping, port etc)
# 
# IN:
# string - monitor ID
#
# OUT:
# n - digit (0 - mean error, 1 - ping, 2 - port, 3 - login, 4 - www, 5 - dns, 6 - external, 8 - troute)
# <string> - configuration file
# 
# USED BY:
# report.pl
#
sub decode_monitor_id {
	my $mon_id = shift;
	$mon_id =~ s/^\s*//;

	# ($env::debug > 1) and wlog "decode_monitor_id: decode: $mon_id\n";
	if ($mon_id =~ /^\d(\d)/) {
		($1 == 1) and return (1, "ping");
		($1 == 2) and return (2, "port");
		($1 == 3) and return (3, "login");
                ($1 == 4) and return (4, "www");
		($1 == 5) and return (5, "dns");
                ($1 == 6) and return (6, "external");
		($1 == 7) and return (6, "monitor");
		($1 == 8) and return (8, "troute");
		($1 == 9) and return (9, "poczta");
	}
	# ($env::debug > 1) and wlog "decode_monitor_id: not detected monitor\n";
	return (0, "");
}

# 
# name: conv
# desc function for checking return code for smtp client
#
# in:
# 
# out:
# number - 0 success, 1 failed
#
# USED BY:
# <local>: send_mail_att
#
sub conv {
        my $sock = shift;
        my $good_code = shift;
        my $sent = shift;
        my $line = <$sock>;

        my $code = substr $line, 0, 3;
        $env::debug and wlog "read from socket: $line\nCODE: $code\n";
        if ($code == $good_code) {
                defined $sent  or return 1;
                $env::debug and wlog "SENT: $sent\n";
                if (!(syswrite SOCK, "$sent\n")) {
                        $env::debug and wlog "conv: BLAD sent $sent: $!\n";
                        return 1;
                }
                return 0;
        }
        wlog "received $line expected code $good_code\n";
        return 1;
}
#
# name: conv_v2
# desc:function for checking return code for smtp/ftp/pop3 clients
# conv_v2 differ from conv return code
#
# IN:
# socket - for read/write 
# good_code - expected 3 chars code 
# sent - if good_code received, sent this command
#
# OUT:
# 0 - all good
# 1 - received not excepcted code (timeout)
# (<return code>, <line>)
#
# USED BY:
# login.pl: get_login
#
sub conv_v2 {
        my $sock = shift;
        my $good_code = shift;
        my $sent = shift;
        my $ret = 1;
        #
        # read data from socket 
        #
	$env::debug and wlog "conv_v2: waiting for initial data\n";
        my $line = <$sock>;
	if ($line) {
		$line =~ s/(\s*)$//g;
        	#
        	# extract 3 chars code
		#
        	my $code = substr $line, 0, 3;
        
        	$env::debug and wlog "conv_v2: CODE $code - line: $line\n";
        
        	if ($code eq $good_code) {      
                	$ret = 0;
                	if (defined $sent) {                                    
                        	$env::debug and wlog "conv_v2: SENT $sent\n";
				$sent .= "\n";
				my $l = length $sent;	
				my $sum = 0;
				#
				# syswrite - becuase of raw write
				# substr - becauase SSL layer has only 16k and we need to repeat 
				# syswrite if buffer is greater than SSL buffer
				#
				for (; $sum < $l;) {
					my $s = syswrite $sock, "$sent";
					if (! defined $s) {
                                		$env::debug and wlog "conv_v2: BLAD sent on $sum bytes: $!\n";                        
                                		$ret = 1;               
						last;
                        		}
					$sum += $s;
					$sent = substr $sent, $s;
					$env::debug and wlog "conv_v2: sent $sum of $l\n";
					# sleep 1;
				}
                	}       
        	} else {
                	$env::debug and wlog "received $line expected code $good_code\n";
        	}
	} else {       
		$env::debug and wlog "conv_v2: ERROR: no received line from socket: $!\n";
        	 $line = "line to receive not defined";
        }
        return wantarray ? ($ret, $line) : $ret;
}
#
# generate Date line for e-mail header
# in: 
# timestamp for which we should generate date
# out:
# string with date 
#
sub get_mail_date {
	#
	# abbrevation for month and day names
	#
	my ($t) = @_;
        my @day = ("Sun", "Mon" , "Tue" , "Wed" , "Thu" ,"Fri" , "Sat" , "Sun");
        my @mon = ("Jan" ,"Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec");
        my @t = localtime();
        my $dt = $t[6];
        my $m = $t[4];
        my $zone = "CEST";
        $t[8] or $zone = "CET";
        return sprintf "$day[$dt], %02d %s %04d %02d:%02d:%02d %s", $t[3], $mon[$m], $t[5] + 1900, $t[2], $t[1], $t[1], $zone;
}

#
# name: send_mail_mta
# desc:function send e-mail using internal e-mail server (postfix), this is used, when direct connection to MX don't works and we like send this e-mail later
#
# in:
# 1 - subject
# 2 - body
# 3 - to address (can be more address separated by space)
# out:
# 0 - don't send to eny one
# >0 - numbers of delivered e-mails
#
# USED BY:
# report.pl: MAIN
#
sub send_mail_mta {
	my ($subject, $body,$tom) = @_;
	my $r = 0;
	my $e =  "/usr/bin/mail -a 'X-Orig: $mail_from' -a 'FROM: CMIT.NET.PL <$mail_from>' -a 'MIME-Version: 1.0' -a 'Content-type: text/html; charset=UTF-8' -s '$subject' $tom";
	# my $e = 'perl -e \'$l = <STDIN>; print $l\';';
	$env::debug and wlog "send_mail_mta: send email to $e\n";
	if (open MAIL, " | $e") { 
		$env::debug and wlog "send_mail_mta: send text: $body\n";
		print MAIL $body;
		print MAIL "\n";
		close MAIL;
		$r = 1;
	} else {
		$env::debug and wlog "send_mail_mta: error in open file $e: $!\n";
	}
	return $r;
}
#
# name: send_mail_att
# desc: function send e-mail using direct connection to MX server 
# for each e-mail address separate header is build
#
# in: 
# 1 - subject
# 2 - body
# 3 - to address (can be more address separated by space)
# 4 - attachments
#
# out:
# int - 0 - don't send to anyone , >0 - numbers of delivered e-mails
# txt - error test
#
# USED BY:
# <local>: send_mail
# report.pl: MAIN

sub send_mail_att {
        my ($subject, $body,$tom, @att) = @_;
        my $e = "\r\n";
	# my $timeout = $main::timeout;
        my @to_m = split /\s+/, $tom;
	my $sent = 0;
	my $mail_from_t = "CMIT.NET.PL";
    defined $main::mail_from_title and $mail_from_t = $main::mail_from_title;

       #
       # for each e-mail recipients sent separate e-mail
       #
	my $af_inet     = 2;
        my $pf_inet     = 2;
        my $sock_stream = 1;
	my $gtime = time();
	my $gdate = get_mail_date($gtime);

	my @chars = ("a".."z" , "A".."Z", 0..9); 
	my $mess_id = join "", map { @chars[rand @chars] } 1 .. 20;
	$mess_id .= ".".$mail_from;
        foreach my $dla (@to_m) {
		$dla =~ s/^\s+//;
		$dla =~ s/\s+$//;
		my $boundary = "--very_long_line_to_divide_email_sections";
                $env::debug and wlog "poczta dla $dla\n";
                #
                # build mail header
                #
                
                my $mess = "From: \"$mail_from_t\" <$mail_from>\n";
		
                $mess .= "Subject: $subject\n";
		$mess .= "Date: $gdate\n";
		$mess .= "Message-ID: <$mess_id>\n";
                $mess .= "To: <$dla>\n";
                $mess .= "MIME-Version: 1.0\n";
		if (@att) {
			$mess.= "Content-Type: multipart/mixed; boundary=\"$boundary\"\n\nMultipart message\n--$boundary$e";
			$mess .= "Content-Type: text/html; charset=UTF-8$e$e";

        		$mess .= "$body$e$e--$boundary";
			foreach my $zal (@att) {				
		                $mess .= "$e$zal$e";
               			$mess .= "--$boundary";
        		}
        		$mess .= "--$e";
		} else {
                	$mess .= "Content-type: text/html; charset=UTF-8$e$e";
			$mess .= "$body";
		}
		#
		# end
		#
                $mess .= "$e$e.$e";
                #
                # exclude hostname from e-mail address to check to which MX we should connected
                #
		# print $mess;
		# next;
                my @smail = split /\@/, $dla, 2;
                if (!defined $smail[1]) {
                        wlog "adres $dla nie ma serwera\n";
			next;
                }
                my $res = Net::DNS::Resolver->new;

                my  @mx = Net::DNS::mx($res, $smail[1]);
                if (!@mx) {
                        wlog "adres $smail[1] brak adresu MX: ".$res->errorstring."\n";
                        next;
                }
                my $proto = getprotobyname('tcp');
                my $mx_ok = 0;
                #
                # try send e-mail to mx server taken from e-mail address
                # if first mx failed, try next on list
                #
		my $t_o = $main::timeout / @mx;
		($t_o < 5) and $t_o = 10;

                foreach my $rmx (@mx) {
                        my $serwer = $rmx->exchange;
			my $mx_code = 1;
			my $sock;
 			$env::debug and wlog "SERWER MX: $serwer\n";

                        eval {
				my $err = 0;
				
                                 local $SIG{ALRM} = sub {
                                        $env::debug and wlog "ALARM pass dla $serwer t_o $t_o (set timeout $main::timeout) sec.\n";
                                        $err = "Timeout";
                                         die "Timeout";
                                 };
                                alarm $t_o;
				#
				# try first SSL connection
				#
				$sock = IO::Socket::SSL->new(
					PeerHost => $serwer,
        				PeerPort => "smtps",
					SSL_verify_mode => SSL_VERIFY_NONE
				);

				if (! defined ($sock)) {
                                        $mx_code = 0;
                                        $env::debug and wlog "send_mail_att: OPENSSL BLAD error=$!, ssl_error=$SSL_ERROR\n";
                                } else {
                                        $env::debug and wlog "send_mail_att: OPENSSL to $serwer $sock\n";
                                }

				#
				# mx_code 0 mean that security connection failed
				# try old 25 port instead
				#
				if (! $mx_code)  {
					my $iaddr = Socket::inet_aton($serwer);
                        		if (!$iaddr) { wlog "serwer $serwer blad inet_aton\n";next; }

					my $paddr = Socket::sockaddr_in("25", $iaddr);
	                                if (!(socket($sock, $pf_inet, $sock_stream, $proto))) {
	                                        $env::debug and wlog "BLAD socket dla $serwer $!\n";
	                                        $err = "socket: $!";
	                                        die;
	                                }
	
					if (!(connect($sock, $paddr))) {
	                                        $env::debug and wlog "BLAD connect dla $serwer $!\n";
	                                        $err = "connect: $!";
	                                        die;
	                                }
				} 
	
				#
				# we can die here, because we are in eval function
				#
                                conv_v2($sock, "220", "HELO cmit.net.pl") and die "No greetings\n";
                                conv_v2($sock, "250", "MAIL FROM: <$mail_from>") and die "HELO no accepted\n";
                                conv_v2($sock, "250", "RCPT TO: <$dla>") and die "Mail From no accepted\n";
                                conv_v2($sock, "250", "DATA") and die "RCPT TO no accepted\n";
				#
				# give more time before data
				# 
				alarm (2 * $t_o);
                                conv_v2($sock, "354", $mess) and die "DATA no accepted\n";
                                conv_v2($sock, "250", "QUIT") and die "Message no accepted\n";
				$mx_ok = 1;
                                $sent++;
				#
				# wait only 5 seconds for QUIT
				# (2s can sometimes be too short for gmail)
				#
				alarm $t_o;
                                my $end = <$sock>;
				$env::debug and wlog "send_mail: get last data\n";
                        };
			
			alarm 0;
			if (defined $sock) {
				close $sock or wlog "close: $!";
			}
                        if ($@) {
                                $env::debug and wlog "send_mail: Error: $@";
                        }
                        $mx_ok and last;
                }
        }
	$env::debug and wlog "send_mail: send $sent e-mails\n";
	return $sent;
}

#
# name: send_mail_verbose
# desc: function send e-mail using direct connection to MX server
# it use by get_poczta as get more parameters and it's more detailed
#
# in:
# 1 - subject
# 2 - body
# 3 - to address (can be more address separated by space)
#
# out:
# int - 0 - don't send to anyone , >0 - numbers of delivered e-mails
# txt - error test
#
# USED BY:
# <local>: get_poczta
#

sub send_mail_verbose {
        my ($protocol, $port, $subject, $body,$tom) = @_;
        my $e = "\r\n";
        # my $timeout = $main::timeout;
        my @to_m = split /\s+/, $tom;
        my $sent = 0;
        my $mail_from_t = "CMIT.NET.PL";

       #
       # for each e-mail recipients sent separate e-mail
       #
        my $af_inet     = 2;
        my $pf_inet     = 2;
        my $sock_stream = 1;
        my $gtime = time();
        my $gdate = get_mail_date($gtime);

        my @chars = ("a".."z" , "A".."Z", 0..9);
        my $mess_id = join "", map { @chars[rand @chars] } 1 .. 20;
        $mess_id .= ".".$mail_from;
        my $err = "OK";
        foreach my $dla (@to_m) {
                $dla =~ s/^\s+//;
                $dla =~ s/\s+$//;
                $env::debug and wlog "poczta dla $dla\n";
                #
                # build mail header
                #

                my $mess = "From: \"$mail_from_t\" <$mail_from>\n";

                $mess .= "Subject: $subject\n";
                $mess .= "Date: $gdate\n";
                $mess .= "Message-ID: <$mess_id>\n";
                $mess .= "To: <$dla>\n";
                $mess .= "MIME-Version: 1.0\n";
                
                $mess .= "Content-type: text/plain; charset=UTF-8$e$e";
                $mess .= "$body";

                #
                # end
                #
                $mess .= "$e$e.$e";
                #
                # exclude hostname from e-mail address to check to which MX we should connected
                #
                # print $mess;
                # next;
                my @smail = split /\@/, $dla, 2;
                if (!defined $smail[1]) {
                        wlog "adres $dla nie ma serwera\n";
                        next;
                }
                my $res = Net::DNS::Resolver->new;
		                my  @mx = Net::DNS::mx($res, $smail[1]);
                if (!@mx) {
                        wlog "adres $smail[1] brak adresu MX: ".$res->errorstring."\n";
                        next;
                }
                my $proto = getprotobyname('tcp');
                my $mx_ok = 0;
                #
                # try send e-mail to mx server taken from e-mail address
                # if first mx failed, try next on list
                #
                my $t_o = $main::timeout / @mx;
                ($t_o < 5) and $t_o = 10;

                foreach my $rmx (@mx) {
                        my $serwer = $rmx->exchange;
                        my $mx_code = 1;
                        my $sock;
                        $env::debug and wlog "SERWER MX: $serwer\n";

                        eval {
                                my $err = 0;

                                 local $SIG{ALRM} = sub {
                                        $env::debug and wlog "ALARM pass dla $serwer t_o $t_o (set timeout $main::timeout) sec.\n";
                                        $err = "Timeout";
                                         die; 
                                 };
                                alarm $t_o;
                                #
                                # try first SSL connection
                                #
				if ($protocol =~ /^SMTPS/) {
                                	$sock = IO::Socket::SSL->new(
                                        	PeerHost => $serwer,
						PeerPort => $port,
                                        	SSL_verify_mode => SSL_VERIFY_NONE
                                	);

                                	if (! defined ($sock)) {
                                        	$env::debug and wlog "send_mail_verbose: OPENSSL BLAD error=$!, ssl_error=$SSL_ERROR\n";
						$err = "OPENSSL ERROR=$!, SSL=$SSL_ERROR";
                                         	die; 
					}
                                        $env::debug and wlog "send_mail_verbose: OPENSSL to $serwer $port $sock established\n";
				}

                                #
                                # mx_code 0 mean that security connection failed
                                # try old 25 port instead
                                #
				if ($protocol =~ /SMTP$/) {
                                        my $iaddr = Socket::inet_aton($serwer);
                                        if (!$iaddr) { wlog "serwer $serwer blad inet_aton\n";next; }

                                        my $paddr = Socket::sockaddr_in($port, $iaddr);
                                        if (!(socket($sock, $pf_inet, $sock_stream, $proto))) {
                                                $env::debug and wlog "BLAD socket dla $serwer $!\n";
                                                $err = "socket: $!";
                                                die;
                                        }

                                        if (!(connect($sock, $paddr))) {
                                                $env::debug and wlog "BLAD connect dla $serwer $!\n";
                                                $err = "connect: $!";
                                                die;
                                        }
                                }
				if (! defined ($sock)) {
					$err = "unkown proto: $protocol";
					$env::debug and wlog "send_mail_verbose: $err\n";
					die;
				} 
                                #
                                # we can die here, because we are in eval function
                                #
                                my ($r, $er) = conv_v2($sock, "220", "HELO cmit.net.pl");
				if ($r) {
					die "No greetings: $er\n";
				}
                                ($r, $er) = conv_v2($sock, "250", "MAIL FROM: <$mail_from>");
				if ($r) {
					die "HELO no accepted: $er\n";
				}
                                ($r, $er) = conv_v2($sock, "250", "RCPT TO: <$dla>"); 
				if ($r) {
					die "Mail From no accepted: $er\n";
				}
                                ($r, $er) = conv_v2($sock, "250", "DATA");
				if ($r) {
					die "RCPT TO no accepted: $er\n";
				}
                                #
                                # give more time before data
                                #
                                alarm (2 * $t_o);
                                ($r, $er) =  conv_v2($sock, "354", $mess);
				if ($r) {
					 die "DATA no accepted: $r\n";
				}
                                ($r, $er) =  conv_v2($sock, "250", "QUIT");
				if ($r) {
					$err = "Message no accepted: $r";
					die;
				}
                                $mx_ok = 1;
                                $sent++;
                                #
                                # wait only 5 seconds for QUIT
                                # (2s can sometimes be too short for gmail)
                                #
                                alarm $t_o;
                                my $end = <$sock>;
                                $env::debug and wlog "send_mail: get last data\n";
                        };

			alarm 0;

                        if (defined $sock) {
                                close $sock or wlog "close: $!";
                        }
                        $err = "OK";
                        if ($@) {
                                $env::debug and wlog "send_mail: Error: $@";
                                $err = "Timeout";
                        }
                        $mx_ok and last;
                }
        }
        $env::debug and wlog "send_mail: send $sent e-mails\n";
        return ($sent, $err);
}


#
# name: send_mail
# desc: virtual function form send e-mail without attachments
# 0 - subject
# 1 - body
# 2 - to

# OUT: 
# same as send_mail_att
# 
# USED BY:
# <local>: send_info
# reminder.pl: MAIN
# report.pl: MAIN
#
sub send_mail {
	return send_mail_att($_[0], $_[1], $_[2]);
}

#
# name: send_http_v4
# desc: function send HTTP(S) request (GET request)
#
# in:
# 1 - HTTP(S) server name (without http or https)
# 1 - timeout in seconds
# 3 - protocol - HTTP/HTTPS
# 4 - port (80 default)
# 5 - line with address 
# 6 - data to send for POST
# 7 - cookie
#
# out:
# n - status (0, failed, 1 good)
# string with server header
# array (description, why failed, or return page from HTTP server)
#
# used by:
# <local>: sms_send
# <local>: send_info
# login.pl: get_www_v2
# 
sub send_http_v2 {
	return send_http_v3(@_);
}

sub send_http_v3 {
	return send_http_v4(@_);
}

sub send_http_v4 {
	# my ($serwer, $time_out, $http_proto, $port, $page, $pem_key) = @_;
	my ($serwer, $time_out, $http_proto, $port, $page,  $data, $cookie) = @_;

        my $proto = getprotobyname('tcp');
	my $server_head = "Unknown";

	my @html;
	 
	my $err = "";
	#
	# more checks
	#
	if ((! $port) || (! ($port > 0))) {
		$err = "Port not defined or not in range"; 
		$env::debug and wlog "send_http: Error: $err\n";
                return (0, "$err");
	
	}
	#
	# check, is page start with / if not add lider /
	#
	($page =~ m|^/|) or  $page = "/$page";

	 $env::debug and wlog "send_http_v4: serwer: $serwer proto: (HTTP or HTTPS) $http_proto and port: $port page $page\n";
	#
	# is perm key is defined
	# then use CURL - currently not used (in past MultiInfo)
	#
	#
	# normal internal wget
	#
	my $pf_inet     = 2;
       	my $sock_stream = 1;

	eval {
		local $SIG{ALRM} = sub {
			$env::debug and wlog "send_http_v4: ALARM pass dla $serwer $time_out sec.\n";
			$err = "Timeout";
			die "Timeout";
		};
		alarm ($time_out);
		my $iaddr = Socket::inet_aton($serwer);
                ($iaddr) or return (0, $server_head, "send_http_v4: can not resolve name $serwer\n");
		my $ip_hex = join('.', map { sprintf("%02X", ord($_)) } split(//, $iaddr));
		$server_head = join('.', map { hex($_) } split(/\./, $ip_hex));

   		my $line;
		if ((defined $data) && ($data)) {
			$line = "POST $page HTTP/1.1\r\n";
			$line .= "Content-Type: application/x-www-form-urlencoded\r\n";
			$line .= "Content-Length: ".length($data)."\r\n";
		} else {
			$line = "GET $page HTTP/1.1\r\n";
		}

		$line .= "HOST: $serwer\r\n";
		$line .= "User-Agent: CMIT.NET.PL (autobot)\r\n";
		$line .= "Accept: */*\r\n";
		$line .= "Connection: close\r\n";
		if ((defined $cookie) && ($cookie)) {
			$line .= "Cookie: $cookie\r\n";
		}
		if ((defined $data) && ($data)) {
			 $line .= "\r\n";
                        $line .= $data;
		}
		 $line .= "\r\n\r\n";

		$env::debug and wlog "send_http_v4: server IP: server $serwer server_head $server_head\nLINE: $line\n";

		if ($http_proto eq "HTTPS") {
			# $serwer =~ s/^https:\/\///;
			#
			# not Net::SSLeay::get_https as follow 
			# using RAW https connection as we like to use own HTTP HEADER
			#
			require Net::SSLeay;
			$Net::SSLeay::trace = $SSL_trace;
			my ($site, $errs, $cert) = Net::SSLeay::https_cat($server_head, $port, $line);
			$cert and  Net::SSLeay::X509_free($cert);
	
			if ($site) {
				# $env::debug and wlog "send_http_v4: HTTPS result $site\n";
				@html = split /\n/, $site;
			} else {
				$env::debug and wlog "send_http_v4: HTTPS result NULL\n";
			}
			if ($errs) {
				$env::debug and wlog "send_http_v4: errs: $errs\n";
				@html = split /\n/, $errs;
				unshift @html, "HTTP/1.1 900 NET OR SSL ERROR\r\n\r\n";
			}

		} elsif  ($http_proto eq "HTTP") {
			my $paddr = Socket::sockaddr_in($port, $iaddr);

			if (!(socket(SOCK, $pf_inet, $sock_stream, $proto))) {
				$err = "socket: $!";
				$env::debug and wlog "send_http_v4: BLAD socket dla $serwer $err\n";
				alarm 0;
				die "$err";
			}
		
			if (!(connect(SOCK, $paddr))) {
				$err = "connect: $!";
				$env::debug and wlog "send_http_v4: BLAD connect dla $serwer $err\n";
				close SOCK or blad "send_http_v4: $!";
				alarm 0;
				die "$err"; 
			}
		
			$env::debug and wlog "send_http_v4: connected to $serwer\n";
			if (!(syswrite SOCK, $line)) {
				$err = "$!";
				$env::debug and wlog "send_http_v4: BLAD write dla $serwer $err\n";
				alarm 0;
				close SOCK or blad "send_http_v4: $!";
				die "$err";
			}
			@html = <SOCK>;            	
			close SOCK or blad "close: $!";	

		} else {
			$env::debug and wlog "send_http_v4: ERROR: http_proto wrongly defined (should be HTTP or HTTPS) is: $http_proto\n";
			die "Internal error\n";
		}
			
		alarm 0;
	};

	if ($@) {
                $env::debug and wlog "send_http_v4: Error: $@ - $err\n";
		return (0, $server_head, "$err");
        }
	
	return (1,$server_head, @html);
}
#
# name: lday
# desc: return name of current directory (which consign from year month day)
#
# in:
# string - user name
# n - time
#
# out:
# string - with consists of: $user/YYYYMMDD
#
# USED BY:
# login.pl: get_www_v2
# login.pl: get_dns
# login.pl: get_login
# login.pl  get_external
# login.pl: get_ping_v2
#
sub lday {
	my $user = shift;
	my @day = gmtime (shift);
	$user or return "lday_nouser/00000000";
        my $ldir = sprintf ("$user/%04d%02d%02d", $day[5] + 1900, $day[4] + 1, $day[3]);
	# system("$main::cl mkdir $ldir");
	
	return $ldir;
};
#
# name: get_file_name
# desc: function generate name of file to get historical data based on account, time and protocol
#
# in:
# 1 - user
# 2 - name
# 3 - proto (protocol, used for suffix)
# 4 - time
#
# out:
# name of file from which get historical data 
#
# USED BY
# <local>: get_file
#
sub get_file_name {
	my $user = shift;
        my $name = shift;
        my $proto = shift;
        my $stime = shift;
        #
        # build file name for current day
        #
        my $ldir = lday($user, $stime);
	my $lfile;

        if (($proto eq "icmp") || ($proto eq "UDP") || ($proto eq "TCP") || ($proto eq "FTP") || ($proto eq "POP3") || ($proto eq "www") || ($proto eq "DNS") || ($proto eq "external")) {
                $lfile = "$ldir/$name-$proto";
        } else  {
		# for SNMP (which has variable suffix)
		$lfile = "$ldir/snmp/$name-$proto";		
	}
	return $lfile;
}
# 
# name: get_file
# desc: function get historical data from last and current files 
#
# in:
# 1 - user
# 2 - stime
# 3 - monitor_id

# out:
# buffer from files
#
# USED BY:
# agent-checktime.pl: check_time
# agent.pl: get_monitor_linear
# agent.pl: get_monitor_grow
# <local>: check_file_v3
# snmp.pl: get_snmp_data
# snmp.pl: get_snmp_net
#
sub get_file_to_delete {
	my $user = shift;
	my $name = shift;
        my $proto = shift;
	my $stime = shift;
	#
	# build file name for current day
	#
	my $lfile = get_file_name($user, $name, $proto, $stime);

	my ($r, @res) = ids_data_get("get", "$lfile");
	#
	# if not much data for current day
	#	
	if (scalar @res < 10) {
		#
       	 	# ask about previous day also
        	#
		$lfile =   get_file_name($user, $name, $proto, $stime - 86400);
		my @res1;

        	$env::debug and wlog "get_file: for previus file exec $lfile\n";

		($r, @res1) = ids_data_get("gett", $lfile);
		unshift @res, @res1;
	}
	return @res;
};

sub get_file_v2 {
        my $stime = shift;
	my $user = shift;
        my $monitor_id = shift;
        #
        # build file name for current day
        #
        my $lfile =  lday($user, $stime)."/$monitor_id";

        # my ($r, @res) = ids_data_get("get", "$lfile");
        my ($r, @res) = ids_data_get("tail", "$lfile");
        # delete first element which is corrupted
        shift @res;
        #
        # if not much data for current day in tail
        #
        if (scalar @res < 10) {
                # 
                #  try get whole file via TCP (as we know that file is big now)
                #
                @res = ();

                ($r, @res) = ids_data_get("gett", "$lfile");
                if (scalar @res < 10) {
	                #
	                # if still not enought data ask about previous day also
	                #
	                $lfile =  lday($user, $stime - 86400)."/$monitor_id";
	                my @res1;
	
	                $env::debug and wlog "get_file_v2: for previus file exec $lfile\n";
	
	                ($r, @res1) = ids_data_get("gett", $lfile);
	                unshift @res, @res1;
                }
        }
        return @res;
};

#
# name: send_data
# desc:send data do IDS (obsolute) - send_data_v2 should be used
# diff: send_data_v2 has addtional paramter which point is action is succes or failed
#
# in args
# 1 - file names
# 2 - buffer to write to file
# out:
# number on how many IDSes we write buffer  succesfully 
#
# USED BY:
# agent-checktime.pl: check_time
# local: get_monitor_linear
# local: get_monitor_grow
# login.pl: get_www_v2
# login.pl: get_dns
# login.pl: get_login
# login.pl: get_external
# login.pl: get_ping_v2
# snmptrapd.pl: MAIN
#
sub send_data {
	my $lfile = shift;
	my $buf = shift;
	my $exec = "$main::cl spart_c \"$lfile\"  \"$buf\n\"";
       # $env::debug and wlog "send_data: $exec\n";
	my $ret = system($exec);
	if ($ret == -1) {
		$env::debug and wlog "send_data: I ret -1 $!\n";
		return 0;
	}
	# error with client (coredump)
	if (($ret & 127) || ($ret & 128)) {
		$env::debug and wlog "I ret oddalo $ret coredump\n";
		return 0;
	}

	$ret >>= 8;
	$env::debug and wlog "send_data: ret oddalo $ret dla $lfile\n";
	return $ret;
};
#
# name: send_data_v2
# desc:send data do IDS
#
# in args
# 1 - file names
# 2 - buffer to write to file
# 3 - type of data
# 	0 - action failed (use IDS spart , no buffer) - data are immediate push to IDSes, 
#	1 - action sucessful and can be buffer (e.g. for data) (use IDS spartb)
#	2 - buffer and go to background (we not require return code)
#	3 - buffer data with debug
#
# out:
# number on how many IDSes we write buffer  succesfully
#
# USED BY:
# agent-checktime.pl: check_time
# local: get_monitor_linear
# local: get_monitor_grow
# login.pl: get_www_v2
# login.pl: get_dns
# login.pl: get_login
# login.pl: get_external
# login.pl: get_ping_v2
# snmptrapd.pl: MAIN
#
sub send_data_v2 {
	my ($lfile, $buf, $type) = @_;
	my $exec;
	#
	# for www_api not use buffer
	#
	if ($main::www_api) {
		$exec = "$main::cl spart_c \"$lfile\" \"$buf\n\"";
	} elsif ($type == 3) {
		$exec = "$main::cl -debug spartb_c \"$lfile\" \"$buf\n\"";
	} elsif ($type == 2) {
		$exec = "$main::cl spartb_c \"$lfile\" \"$buf\n\" &";
	} elsif ($type == 1) {
		$exec = "$main::cl spartb_c \"$lfile\" \"$buf\n\"";
	} else {
        	$exec = "$main::cl spart_c \"$lfile\" \"$buf\n\"";
	}

        $env::debug and wlog "send_data_v2: $exec\n";
        my $ret = system($exec);
        if ($ret == -1) {
                $env::debug and wlog "send_data_v2: I ret -1 $!\n";
                return 0;
        }
        # error with client (coredump)
        if (($ret & 127) || ($ret & 128)) {
                $env::debug and wlog "send_data_v2: I ret oddalo $ret coredump\n";
                return 0;
        }

        $ret >>= 8;
        $env::debug and wlog "send_data_v2: ret oddalo $ret dla $lfile: $buf\n";
        return $ret;
};

#
# name: check_file_v3
# desc: analyze historical file
# return good or fail status and time, when last status started
#
# in args
# 1 stime - start time - current time
# 2 - user (with /konto prefix )
# 3 - monitor_id
#
# out:
# 1 status:
#       0 - no action require (last data are good and  is too young, less than 3 minutes)#
#       1 - success but action should be taken (last data are good but data is older than 3 minutes)
#       2 - failed, but not approved by 2 other servers
#       3 - failed and approved by 2 other servers
#
# 2. time - when last action/status started
# 3. time - time of last action (ltime)
#
# USED BY:
# login.pl: MAIN
#

sub check_file_v3 {
        my $stime = shift;
        my $user = shift;
	my $monitor_id = shift;

        my @dane;
        my $good_code = 0;
        #
        # determine is monitor WWW
	# if yes, then change good_code to 200
        #
	if ($monitor_id =~ /^\d(\d)/) {
		my $proto = $1;
        	if ($proto == 4) {
                	$good_code = 200;
		}
        }
        @dane = get_file_v2($stime, $user, $monitor_id);
        my $lcode = 1001;
        my $ltime = 0;
        my $wrong = 0;
        my $good = 0;
        my %server = ();

        foreach (@dane) {
                # (time when action occure) - time duration - status ( 0 - OK, 1001 our Timeout)
                if (/^(\d+)\s+[\d\.]+\s+(\d+)\s+(\w+)/) {
                        $ltime = $1;
                        $lcode = $2;
                        my $host = $3;
                        chomp $host;
                        if ($lcode != $good_code) {
                                #
                                # don't count server where we start
                                #
                                ($host ne $main::hostname) and $server{$host} = $1;

                                $good = 0;
                                $wrong or $wrong = $ltime;
                        } else {
                                %server = ();
                                $wrong = 0;
                                $good or $good = $ltime;
                        }
                }
        }

	my $k = keys (%server);
        $env::debug and wlog "check_file_v3: wrong $wrong good $good stime $stime number of keys $k\n";
        if ($wrong) {
                if ($k > 0) {
                        foreach my $kk (keys(%server)) {
                                $env::debug and wlog "check_file_v3: ALARM - keys $kk value ".$server{$kk}."\n";
                        }
                        return (3, $wrong, $ltime);
                }
                return (2, $wrong, $ltime);
        }
	#
	# if data from file are to young (default is less than 45s)
	# and this isnt pref ids
	# then, no action to take
	#
	if ((! $main::ask_pref_ids) && (($stime - $ltime) < $env::good_time) && (! $main::www_api)) {
		$env::debug and wlog "check_file_v3: current time $stime Last time from file $ltime and code $lcode - ask to skip\n";
		 return (0, $good, $ltime);
	}
        return (1, $good, $ltime);

}
#
# check alarm file, is 
# alarm in passed
# IN:
# $alarm_off - how many hours we should send information
# @data - data from alarm file
# OUT
# 0 - alarm still vaid
# n - wrong time, when first alarm occur 
#

sub check_pass_time
{
	my ($ctime, $alarm_off, @data) = @_;
 	#
        # check data from alarm file
        # there is alarm file and alarm_off variable is set
        #
         my  $alarm_send = 0;
	my $wrong = 0;

        foreach (@data) {
        	(/<alarm_send:(\d+)/) and $alarm_send = $1;
                (/<stime:(\d+)/) and $wrong = $1;
        }

        $env::debug and wlog "check_pass_time: alarm_send $alarm_send alarm_off $alarm_off ctime $ctime\n";
        #
        # if alarm_off is created than alarm send
        # then send alarm again
        #
        ($alarm_send + (3600 * $alarm_off) < $ctime) and return $wrong;

	return 0;
}
sub create_file_alarm {
}
#
# name: send_info
# desc: function send info to customer
# 	if sms is configured, sms is sent
# 	if email is configured e-mail is sent
#
# in:
# action - what kind of action, "alarm", "good"
# user - user with /konto prefix
# name - name input by user or server name (disk, net)
# proto - (icmp, www, port, disk, net)
# wrong - time from when start problems
# alarm_off - hours after which we should send again alarms
# detail - add additional information about problem
# name1 - name of resources for proto = "net" or "disk"
#
# out:
# 0 - failed
# n - numbers of alarms send
#
# USED BY
# snmp.pl: get_snmp_data
# snmp.pl: get_snmp_net
# login.pl: MAIN
#
sub send_info
{
	my $action = shift;
	my $user = shift;
	my $name = shift;
	my $monitor_id = shift;
	# use by simple monitor
	# 0 for snmp
	my $group = shift;
	# for simple: ping,port
	# for snmp: net, disk...
	my $proto = shift;
	my $wrong = shift;
	#
	# for snmp: 0
	my $alarm_off = shift;
	my $detail = shift;
	my $name1_orig;
	my $filen;
	local $mail_from = "alarm\@cmit.net.pl";

	my $snmp = 0;
	#
	# for agent/SNMP addtional parameter is in parameter list
	#
	if (($proto eq "net") || ($proto eq "disk") || ($proto eq "memory") || ($proto eq "cpu") || ($proto eq "diskio") || ($proto eq "disk_inode")) {
		my $name1 = shift;
		$name1_orig = $name1;
		$name1 =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
		$filen = "$user/alarm-$monitor_id-$proto-$name1";
		$snmp = 1;
	#
	# for group defined
	#
	} elsif ($group) {
		$filen = "$user/alarm-$group";
	#
	# for the rest
	#
	} else {
		$filen = "$user/alarm-$monitor_id";
	}
	
	#
	# check, if is there  any alarm file exist ?
	#	
	my $jest = 0;
	my ($jest1, @data) = ids_data_get ("get", $filen);
	$env::debug and wlog "ALARM: checking file $filen with jest $jest1\n";
	($jest1 < 0) and return 0;
	#
	# check is alarm is raised or is raised by another groups member 
	#

	if ($snmp) {
		($jest1) and $jest = 1;
	}  elsif ($jest1) {
		foreach (@data) {
			$env::debug and wlog "send_info: match: $_\n to: <proto:$proto/>|) && (m|<server:$name/>\n";
			((m|<protocol:$proto/>|) && (m|<name:$name/>|)) and $jest = 1;
			if (m|<action:freeze/>|) {
				$env::debug and wlog "send_info: action done by freeze...exiting\n";
				return 0;
			}
			$env::debug and wlog "send_info match: $_\n to: <proto:$proto/>|) && (m|<server:$name/>\n";
                        ((m|<protocol:$proto/>|) && (m|<name:$name/>|)) and $jest = 1;

			$env::debug and wlog "send_info: alarm raised by us\n";
		}
		if (! $jest) {
			 $env::debug and wlog "send_info: alarm already in this group, but not raised by this monitor !!\n";
			return 0;
		}
	}

	my $do = 0;
	my $emaila_subject = "";
	# pure short description for SMS (try to be max 150 chars) without polish letter
	my $txt_sms = "";
	# whole information to e-mail with html  with polish letter (html with header and footer)
	my $txt_email = "";
	# pure description for others systems without polish letter
	my $txt_desc = "";
	my $typ = "NONE";

	$env::debug and wlog "send_info: language $language lang $lang\n";
	# 
	# 2 cases when alarm can be send
	# -  if there is alarm and alarm file not exist
	# - is alarm and alarm file exist and repeat time passed
	# 
	my $ctime = time();

	if ($action eq "alarm") {
		 #
	        # check data from alarm file
	        # there is alarm file and alarm_off variable is set
	        #
	         my $pass_time = 0;
		#
		# check alarm file and update $wrong if nessesary
		#	
	        if (($jest) && ($alarm_off)) {
	                $pass_time = check_pass_time($ctime, $alarm_off, @data);
			$pass_time and $wrong = $pass_time;
	         }
	
		if ((!$jest) || ($pass_time)) {
			#
			# create file with alarm
			# only to inform that we working on send info to external sysytems
			# if received any number,update thise line
			#
			my $eline = "<name:$name/><ids:$main::hostname/><protocol:$proto/><stime:$wrong/><alarm_send:$ctime/>";
			#
			# if exist add device name (for SNMP)
			#
			$name1_orig and $eline .= "<device:$name1_orig/device>";
			#
			# if exist add group name (it's faster to get group name
			# from file then match it from alarm name (where is only digit)
			#
			$group and $eline .= "<group:$group/>";
			#
			# add to alarm history
			#
			my $sent = send_data_v2 ("$user/history/alarms", "$eline<action:alarm/>", 0);
			if ($sent < 2)  {
				$env::debug and wlog "send_info: can't add alarm to history, write only to $sent IDS\n";
				return 0;
			}
			#
			# trune to be sure that we are first alarm file
			#
	
			my $ret = system("$main::cl trune_r \"$filen\" \"$eline\n\"");
			
			$ret >>= 8;
			
			#
			# and send e-mail to e-mail alarm
			#
			if ($ret > 1) {	
				my $who = $user;
				$who =~ s|/konto/||;
				$txt_email = $lang->{'hello'}." $who,<br>";
				my $ltxt;
			
				if ($proto eq "icmp") {
					$typ = "urządzenie";
					$ltxt = $lang->{'send_info_1'};
				} elsif ($proto eq "port") {
					$typ = "port";
					 $ltxt = $lang->{'send_info_2'};
				} elsif ($proto eq "external") {
                                        $typ = "external";
					 $ltxt = $lang->{'send_info_3'};

				} elsif ($proto eq "www") {
					$typ = "strona";
					 $ltxt = $lang->{'send_info_4'};

				} elsif ($proto eq "DNS") {
                                        $typ = "DNS";
					 $ltxt = $lang->{'send_info_5'};

				 } elsif ($proto eq "login") {
                                        $typ = "autoryzacja";
					 $ltxt = $lang->{'send_info_6'};
				} elsif ($proto eq "troute") {
                                        $typ = "trace route";
                                        $ltxt = $lang->{'send_info_7'};
				 } elsif ($proto eq "poczta") {
                                        $typ = "poczta";
                                        $ltxt = $lang->{'send_info_8'};
				} elsif ($proto eq "disk") {
					$typ = "dysk";
					$ltxt = $lang->{'send_info_10'};

				} elsif ($proto eq "net") {
					$typ = "karta sieciowa";
					$ltxt = $lang->{'send_info_11'};
				} elsif ($proto eq "memory") {
					$typ = "Pamięć";
					$ltxt = $lang->{'send_info_12'};
				} elsif ($proto eq "cpu") {
					$typ = "procesor";
					$ltxt = $lang->{'send_info_13'};
				 } elsif ($proto eq "diskio") {
					$typ = "I/O dysk";
					$ltxt = $lang->{'send_info_14'};
				} elsif ($proto eq "disk_inode") {
                                        $typ = "inode";
                                        $ltxt = $lang->{'send_info_15'};

				} elsif ($proto eq "agentcheck") {
					$typ = "agent check";
					 $ltxt = $lang->{'send_info_100'};
					
				} else {
					$typ = "unknown";		
					$ltxt = $lang->{'send_info_101'};
					
				}
				#
				# if not text for SMS then copy it from description
				#
				if (($proto eq "icmp") || ($proto eq "port") || ($proto eq "external") || ($proto eq "www") || ($proto eq "troute") || ($proto eq "poczta") ||
                                ($proto eq "DNS") || ($proto eq "login") || ($proto eq "agentcheck") || ($typ eq "unknown") ) {
					my $name1 = $name;
					# detail: serwer (TEST).
					$detail and $name1 .= " ($detail)";

					# txt_desc: e.g.: Problem z hostem: serwer (TEST).
					# SMS is shorter than other, because sometimes no all information can't fit 160 chars
					# (e.g. when www page is long but we enable it for icmp and port 
					#
					if (($proto eq "imcp") || ($proto eq "port")) {
						# SMS with details
						 $txt_sms = sprintf("$ltxt:".$name1."."); 
					} else {
						# short info without details
						# for Common Use SMS has only title and time - without details as details can be longer than 160 chars
						# txt_sms: e.g.: Problem z hostem: serwer.

						$txt_sms = sprintf("$ltxt:".$name.".");
					}

       	                         	$txt_desc = sprintf($ltxt.": $name1");
       		                        $txt_email .= sprintf($ltxt.": $name1<br>");
                        	}
				if ( ($proto eq "disk") || ($proto eq "net") || ($proto eq "memory") || ($proto eq "cpu") ||
					($proto eq "diskio") || ($proto eq "disk_inode")) {
					 $txt_sms = sprintf($ltxt, $name1_orig, $name);
                                        $txt_desc = sprintf($ltxt." ($detail)", $name1_orig, $name);
                                        $txt_email .= sprintf($ltxt." ($detail)<br>",$name1_orig, $name);
				}
					
				$txt_sms or $txt_sms = $txt_desc;
				$emaila_subject = $lang->{'send_info_20'}." $name";
				$do = 1;
			}
		}
	}
	if (($jest) && ($action eq "good")) {
		#
                # create file with alarm
                # only to inform that we working on send info to external sysytems
                # if recceived any number,update thies line
                #
                my $eline = "<name:$name/><ids:$main::hostname/><protocol:$proto/><alarm_send:$ctime/>";
                #
                # if exist add device name (for SNMP)
                #
                $name1_orig and $eline .= "<device:$name1_orig/device>";
                #
                # if exist add group name (it's faster to get group name
                # from file then match it from alarm name (where is only digit)
                #
                $group and $eline .= "<group:$group/>";

		my $sent = send_data_v2 ("$user/history/alarms", "$eline<action:good/>", 0);
                if ($sent < 2)  {
                 	$env::debug and wlog "send_info: can't add alarm to history, write only to $sent IDS\n";
                       	return 0;
                 }
		#
		# file with alarm exits
		# and they execute us that is ok
		# so, delete file with alarm and send good news
		#
		my ($ret, @data1) = ids_data_get("delete_c", $filen);
		
		#
		# and prepare variables to send this information
		#
		if ($ret > 1) {
			my $who = $user;
			$who =~ s|/konto/||;
			$txt_email = $lang->{'hello'}." $who,<br>";
			my $ltxt;
			if ($proto eq "icmp") {
				$typ = "urządzenie";
				$ltxt = $lang->{'send_info_51'};
			} elsif ($proto eq "port") {
				$typ = "port";
				$ltxt = $lang->{'send_info_52'};
			} elsif ($proto eq "external") {
                                $typ = "external";
				$ltxt = $lang->{'send_info_53'};
			} elsif ($proto eq "www") {
                                $typ = "strona";
				$ltxt = $lang->{'send_info_54'};
			} elsif ($proto eq "DNS") {
                                $typ = "DNS";
				$ltxt = $lang->{'send_info_55'};
			} elsif ($proto eq "login") {
                                $typ = "autoryzacja";
				$ltxt = $lang->{'send_info_56'};
			} elsif ($proto eq "troute") {
                                $typ = "troute";
                                $ltxt = $lang->{'send_info_57'};
			 } elsif ($proto eq "poczta") {
                                $typ = "poczta";
                                $ltxt = $lang->{'send_info_58'};

			} elsif ($proto eq "disk") {
				$typ = "dysk";
				$ltxt = $lang->{'send_info_60'};
			} elsif ($proto eq "net") {
				$typ = "karta sieciowa";
				$ltxt = $lang->{'send_info_61'};
			} elsif ($proto eq "memory") {
				$typ = "Pamięć";
				$ltxt = $lang->{'send_info_62'};
			} elsif ($proto eq "cpu") {
				$typ = "procesor";
				$ltxt = $lang->{'send_info_63'};
			 } elsif ($proto eq "diskio") {
				$typ = "I/O dysk";
				$ltxt = $lang->{'send_info_64'};
			} elsif ($proto eq "agentcheck") {
				$typ = "agent check";
				$ltxt = $lang->{'send_info_65'};
			 } elsif ($proto eq "disk_inode") {
                                $typ = "inode dysk";
                                $ltxt = $lang->{'send_info_66'};

			} else {
				 $typ = "unknown";
				$ltxt = $lang->{'send_info_101'};

			}
			if (($proto eq "icmp") || ($proto eq "port") || ($proto eq "external") || ($proto eq "www") || ($proto eq "troute") || ($proto eq "poczta") || 
				($proto eq "DNS") || ($proto eq "login") || ($proto eq "agentcheck") || ($typ eq "unknown") ) {
				$txt_sms = sprintf($ltxt.".", ": $name");
				my $name1 = $name;
				$detail and $name1 .= " ($detail)";
                                $txt_desc = sprintf($ltxt, $name1);
                                $txt_email .= sprintf($ltxt.".<br>", $name1);
			}

			if ( ($proto eq "disk") || ($proto eq "net") || ($proto eq "memory") || ($proto eq "cpu") ||
                              ($proto eq "disk_inode") || ($proto eq "diskio")) {
                                         $txt_sms = sprintf($ltxt, $name1_orig, $name);
                                        $txt_desc = sprintf($ltxt." ($detail)", $name1_orig, $name);
                                        $txt_email .= sprintf($ltxt." ($detail)<br>",$name1_orig, $name);
                               }

			$emaila_subject = $lang->{'send_info_24'}." $name";

			$do = 1;
		}		
	}
	my @c = localtime($wrong);

        my $cz = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $c[5] + 1900, $c[4] + 1, $c[3], $c[2], $c[1], $c[0]);

	if ($txt_email) {
                $txt_email .= $lang->{'send_info_21'}." $cz.<br>";
                $txt_email .= $lang->{'footer_cmit'};
        }
	if ($txt_sms) {
		$txt_sms .= $lang->{'send_info_21'}." $cz.";
	}

	#
        # if language is polish then convert polish characters
        # perl doesn't support utf-8 as we expect (we can't use simple tr)
        #
        if ($language eq "polski")      {
            if ($txt_sms) {
                $txt_sms =~ s/ą/a/g;
                $txt_sms =~ s/ć/c/g;
                $txt_sms =~ s/ę/e/g;
                $txt_sms =~ s/ó/o/g;
                $txt_sms =~ s/ł/l/g;
                $txt_sms =~ s/ń/n/g;
                $txt_sms =~ s/ś/s/g;
                $txt_sms =~ s/ż/z/g;
                $txt_sms =~ s/ź/z/g;
            }
            if ($txt_desc) {
                $txt_desc =~ s/ą/a/g;
                $txt_desc =~ s/ć/c/g;
                $txt_desc =~ s/ę/e/g;
                $txt_desc =~ s/ó/o/g;
                $txt_desc =~ s/ł/l/g;
                $txt_desc =~ s/ń/n/g;
                $txt_desc =~ s/ś/s/g;
                $txt_desc =~ s/ż/z/g;
                $txt_desc =~ s/ź/z/g;
            }
        }
	#
	# if send is required, send data
	#
	$do and send_info_notification($action,$user, $name, $monitor_id, $wrong, $typ, $txt_sms, $txt_desc, $txt_email, $emaila_subject);
	return 1;
}	
#
# name: send_info_notification
# desc: function send text info to customer providers (sms/e-mail/webservices)
#       if sms is configured, sms is sent
#       if email is configured e-mail is sent
#
# in:
# user - user with /konto prefix
# $typ - polish txt of typ , 
# $txt_sms - SMS messages to send
# $txt_desc - short description 
# $txt_email - email description (with HTML)
# $emaila_subject - subject for e-mail
#
# out:
# 0 - failed
# n - numbers of alarms send (not implemented - always success)
#
# USED BY
# send_info
#

sub send_info_notification {
	my ($action, $user, $name, $monitor_id, $wrong, $typ, $txt_sms, $txt_desc, $txt_email, $emaila_subject) = @_;	
		#
		# get sms number
		#
		my $pid;
		my %child;
		
		my ($p_id, $proto) = decode_monitor_id($monitor_id);
		my ($r, @res) = ids_data_get("get", "$user/notify/on-sms");

		if ($r > 0) {
			my @sms;
			my $sms_count = 0;
	
			foreach (@res) { 
				chomp; 
				if (/(\d{9})/) { 
					push @sms, "--pn=$1"; 
					$sms_count++;
				}
			}
			#
                        # if there are any numbers
                        #
                        if (@sms) {
				#
				# not requireda as it is moved to sms native program
				# $txt_sms =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
				#
         			if ((length $txt_sms > 159)) {
                			$txt_sms = substr $txt_sms, 0, 154;
                			$txt_sms .= "...";
        			}

				$pid = fork();
				if (! defined $pid) { 
					$env::debug and wlog "send_info_notification: fork error for sms: $!\n"; 
				} else {
					if ($pid == 0) { 
					# { and } prevent warning about exec
					# check is user has available SMS, if yes, then decresed it by one
						# return code
						# 0 - OK
						# 1 - exec error 
						# 2 - no SMS available
						my $r_e = 2; 
						my ($r1, @res1) = ids_data_get("get", "$user/counts/sms");
						if ($r1 > 0)  {
							my $sms_nr = $res1[0];	
							$env::debug and wlog "send_info_notification: available $sms_nr count $sms_count SMS\n";
							if (($sms_nr =~ /\d+/) && ($sms_nr > 0)) {
								$sms_nr -= $sms_count;
								($sms_nr < 0) and $sms_nr = 0;
								my $r = system("$main::cl trunc_c \"$user/counts/sms\" \"$sms_nr\"");
						                $r >>= 8;
                						$env::debug and wlog "send_info_notification: new SMS $sms_nr value save return $r\n";

								$r_e = 1;	
								$env::debug and wlog "$sms_cl @sms --text=$txt_sms --cfgdir=$sms_path\n";
                        					exec("$sms_cl",@sms,"--text=$txt_sms", "--cfgdir=$sms_path"); 
							}
						}	
						exit($r_e);
					}
					if ($pid > 0) {  
						$env::debug and wlog "send_info_notification: send $txt_sms to @sms by pid $pid\n";
						$child{$pid} = 0; 
					}
				}
                        } else { $env::debug and wlog "send_info_notificiation: no sms number\n"; }
		} 

		#
		# send e-mail alarm
		#

		($r, @res) = ids_data_get("get", "$user/notify/on-email");

                if ($r > 0) {
			my $emaila = "";
			foreach (@res) { $emaila .= "$_ "; }
			#
			# send email
			#
			if ($emaila) {	
				$pid = fork();
				if (! defined $pid) {
					$env::debug and wlog "send_info_notification: fork error for e-mail: $!\n";
				} else {
					if ($pid == 0) { 	
						send_mail($emaila_subject, $txt_email, $emaila) or send_mail_mta($emaila_subject, $txt_email, $emaila);
						exit (0);
					}
					if ($pid > 0) {
						$env::debug and wlog "send_info_notification: send email to $emaila by pid $pid\n";
						 $child{$pid} = 0;
					}
				}
			} else { $env::debug and wlog "ALARM: no e-mail address\n"; }
		}
		#
		# below isn't required ? same info we have from debug ids_data_get
		# else { wlog "send_info: $user/on-email with $r\n"; }
		#
                # send http
                #

                ($r, @res) = ids_data_get("get", "$user/notify/on-http");
		if ($r > 0) {
			my $host = "";
			my $page = "";
			my $proto_h = "HTTP";
			my $para = "";	
                        foreach my $l (@res) {
                                chomp $l;
				my ($n, $v) = split /\|/, $l;
				if ($n eq "web_serwer") {
					($v =~ /^https:\/\//i) and $proto_h = "HTTPS";
                                        $v =~ s|^https*://||;

					($host, $page) = split /\//, $v, 2;
				#	$env::debug and wlog "send_info_notification: host: $host page $page\n";
					next;
				}
				(($n =~ /^#/) && ($host)) or next;
				$n =~ s/^#//;
                                $v =~ s/OPIS/$txt_desc/;
                                $v =~ s/SYSTEM_NAZWA/$name/;
                                $v =~ s/ALARM_TYP/$typ/;
                                $v =~ s/TIMESTAMP/$wrong/;
				if ($para) { $para .= "&$n=$v";
				} else { $para = "?$n=$v"; }
                        }
                        #
                        # get user data if on-http provide any data
                        #
                        if ($host) {
				#
				# not ids_data_get because we need to sort data when loading
				#
                                my $exec1 = "$main::cl get \"$user/notify/http-$monitor_id-$proto\"";
				# $env::debug and wlog "send_info_notification: get data for particular monitor from: $exec1\n";
                                #
                                # add data for particular alarm
                                #
                                if (open PLIK, "$exec1 | ") {
                                        while (my $l = <PLIK>) {
						chomp $l;
						# $env::debug and wlog "send_info: read $exec1: $l\n";
						my ($n, $v) = split /\|/, $l;

                                                $v =~ s/OPIS/$txt_desc/;
                                                $v =~ s/SYSTEM_NAZWA/$name/;
                                                $v =~ s/ALARM_TYP/$typ/;
                                                $v =~ s/TIMESTAMP/$wrong/;
                                                if ($n =~ /^#/) {
                                                        if ($action eq "alarm") { 
								$n =~ s/^#//;
								if ($para) { $para .= "&$n=$v";
                                				} else { $para = "?$n=$v"; }
							}
                                                } else {
                                                        if ($action eq "good") { 
								if ($para) { $para .= "&$n=$v";
                                                                } else { $para = "?$n=$v"; }
							}
						}
					}
					close PLIK;
				} else { wlog "send_info: error open $exec1 with error $!\n"; }
                        }

                        if ($host) {
				# $env::debug and wlog "send_info: host $host page: $page para: $para\n";
                                $pid = fork();
                                if (! defined $pid) {
                                        $env::debug and wlog "send_info: fork error for http: $!\n";
                                } else {
                                        if ($pid == 0) {
						my $port = 80;
						($proto_h eq "HTTPS") and $port = 443;
						if ($page) { $page .= "$para"; 
						} else { $page = $para; }
                                                my ($rc, $sh,@txt) =  send_http($host, $proto_h, $port, $page);
						((@txt) && ($env::debug)) and wlog "send_info: return: \n@txt\n";
                                                exit $rc;
                                        }
                                        if ($pid > 0) {
                                                $env::debug and wlog "send_info: send httpby pid $pid\n";
                                                $child{$pid} = 0;
                                        }
                                }
                        } else {
                                $env::debug and wlog "send_info: no host in http\n";
                        }
                }
		#
               	# get webservice
               	#			
		# $exec = "$main::cl get \"$user/notify/on-webservice\"";
		($r, @res) = ids_data_get("get", "$user/notify/on-webservice");
		my @web_data;

		if ($r > 0) {
                        foreach my $l (@res) {
				chomp $l;
				$l =~ s/OPIS/$txt_desc/;
				$l =~ s/SYSTEM_NAZWA/$name/;
				$l =~ s/ALARM_TYP/$typ/;
				$l =~ s/TIMESTAMP/$wrong/;
				push @web_data, $l;
			}
			#
			# get user data if on-webservice provide any data
			#
			if (@web_data) {
				my $exec1 = "$main::cl get \"$user/notify/webservice-$monitor_id-$proto\"";
				#
				# add data for particular alarm
				#
				if (open PLIK, "$exec1 | ") { 
					while (my $l = <PLIK>) {
						chomp $l;
						$l =~ s/OPIS/$txt_desc/;
						$l =~ s/SYSTEM_NAZWA/$name/;
						$l =~ s/ALARM_TYP/$typ/;
						$l =~ s/TIMESTAMP/$wrong/;
						if ($l =~ /^#/) {
							if ($action eq "alarm") { push @web_data, $l; }
						} else {	
							if ($action eq "good") { $l = "#".$l; push @web_data, $l; }
						}
					}
					close PLIK;                  			
				} else { wlog "send_info: error open $exec1 with error $!\n"; }
			}
			
			if (@web_data) {
				$pid = fork();
				if (! defined $pid) {  
					$env::debug and wlog "send_info: fork error for webservice: $!\n"; 
				} else {
					if ($pid == 0) { 
						my ($rc, $txt) = send_webservice(@web_data); 
						exit $rc;
					}
					if ($pid > 0) {
						 $env::debug and wlog "send_info: send webservice by pid $pid\n";
                                                $child{$pid} = 0; 
					}
				}
			} else {
				$env::debug and wlog "send_info: no webservice\n";
			}
		} # else {  wlog "send_info: $user/notify/on-webservice return $r\n"; }
		#
		# catch all child
		#
		foreach my $c (keys %child) {
                	$env::debug and wlog "send_info: waiting for $c\n";
                	my $kid = waitpid($c, 0);
                	($kid) and  $env::debug and wlog "child $kid return $?\n";
               		delete $child{$c};
		}
        return 1;
}


#
# name: send_webservice
# desc :send SOAP
#
# in:
# array -  parameters lines - name|value lines, started with # parameters, without connection setting (web_serwer, web_namespace, web_serwis)
# out:
# n - 0/1 - failed/success
# string - comments
#
# USED BY
# <local>: send_info
#
sub send_webservice
{
	my @data = @_;
	my @soap_name;
	my (%web); 

	require SOAP::Lite;

	foreach my $l (@data) {
		$env::debug and wlog "send_webservice: $l\n";
		my @f = split /\|/, $l, 2;
        	if (@f) {
			#
			# if start with # mean parameter and value 
			#
               		if ($f[0] =~ /^#/) {
                        	my $n = $f[0];
                        	$n =~ s/^#//;
				push @soap_name, (SOAP::Data->name($n)->value( $f[1] ));
                	} else {
			#
			# if line without # mean, property value, like webservice host, webservice name
			#
                        	my $n = $f[0];
                        	$web{$n} = $f[1];
                	}
         	}
	}
	my $soap = SOAP::Lite->new( proxy => $web{'web_serwer'});

	$soap->on_action( sub { $web{'web_namespace'}.$web{'web_serwis'} });
	$soap->autotype(0);
	$soap->soapversion('1.2');
	$soap->envprefix('soap12');
	$soap->default_ns($web{'web_namespace'});

	$SOAP::Constants::DEFAULT_HTTP_CONTENT_TYPE  = 'application/soap+xml';
	my $som;
	my $err;

	eval {
		local $SIG{ALRM} = sub {
			$env::debug and wlog "ALARM pass dla ".$web{'web_serwis'}." $main::timeout sec.\n";
                       	$err = "Timeout";
                       die "Timeout";
                 };
                 alarm ($main::timeout);
		#
		# TODO: check, maybe this can go thru send_http
		#		
		$som = $soap->call($web{'web_serwis'}, @soap_name);
		alarm 0;
	};
	if ($som) {
		if ($som->fault) {
			my $t = $som->fault->{ faultstring };
			$env::debug and wlog "$t\n";
			return (0, $t);
		} else {
			$env::debug and wlog $som->result."\n";
			return (1, $som->result);
		}
	} else {
		$env::debug and wlog "send_webservice: timeout\n";
	}
	return (0, "Timeout");
}

#
# name: ids_data_get
# desc: retreive infromation from IDS
#
# in:
# string - command to execute (get, list, rist)
# string - path in IDS to get data
#
# out:
# number -  -1 - failed, number of answers 0 - object no found, 1 - succesfull
# array - when failed, error, when succesfull buffer, each line its line from file
#
# USED BY:
# common_cmit.pm: get_file
# common_cmit.pm: send_info
#

sub ids_data_get {
	my ($command, $file) = @_;
	my ($pid, $i);
	my @buf;
	local(*RH, *WH);
	$SIG{CHLD} = 'DEFAULT';

	for ($i = 0; $i < 3; $i++) {
		#
		# wait, if this is second time
		#
		$i and sleep 1;
		if (! pipe RH, WH) {
			$env::debug and wlog "ids_data_get: error in pipe: $!\n";
			next;
		}
		$pid = fork();
		if (! defined $pid) {
			$env::debug and wlog "ids_data_get: error in fork (probe $i): $!\n";
			next;
		} 

		#
		# CHILD
		#
		if ($pid == 0) {
			close RH;
			open STDOUT, ">&WH" or die "ids_data_get: reopen STDOUT error: $!";
			# { and } prevent warning about exec
            # { print "EXEC $main::cl $command \"$file\""; }

            { exec("$main::cl $command \"$file\""); }

            # print "ids_data_get: real OUTPUT: $main::cl $command \"$file\"";
			$env::debug and wlog "ids_data_get: error in exec: $main::cl $command \"$file\": $!\n";
			exit (-1);
		}
		#
		# PARENT
		# 
		if ($pid > 0) {
			close WH;
			while (<RH>) { 
				chomp; 
                # $env::debug and wlog "ids_data_get: read: $_\n";
				push @buf, $_; 
			}
			close RH;
			if (waitpid($pid, 0)) {
				my $res = $?;
				$res >>= 8;
				$env::debug and wlog "ids_data_get: child: command: $main::cl $command \"$file\" return $res and $?\n";
				
				if (($res < 0) || ($res > 10)) {
					$env::debug and wlog "ids_data_get: error child $file return $res\n";
					next;
				}
				return ($res, @buf);
			} else {
				$env::debug and wlog "ids_data_get: waitpid no pid $pid: $!\n";
			}
		}				
	}
	close RH;
	close WH;
	return (-1, "");
}


return 1;

#
# Get linear information
# 1 - user ( with /konto)
# 2 - name of server
# 3 - monitor_id
# 4 - time
# 5 - alarm_off
# 6 - o_limit - file with limit
# 7 - buf with data
#
sub get_monitor_linear
{
	my ($user, $name, $monitor_id, $stime, $alarm_off, $o_limit, @buf) = @_;
	my (%disk, %cur_disk, $jest_l);
	$jest_l = 0;
	#
	# get disk limits
	#
	my $lim = $user."/monitor/".$monitor_id."/".$o_limit;

	my ($r_ids, @dane) = ids_data_get ("get", $lim);
	
	($r_ids < 0) and return;
	
       	foreach my $n (@dane) { 				
               	($n =~ /^#/) and next; 
		chomp $n;
		#
		# <name>|<limit in MB> <limit in %>
		#
               	my @m = split /\|/, $n, 2;
               	if (! $m[1]) { $env::debug and wlog "get_monitor_linear: brak limitow w $m[0]\n"; next; }
               	$disk{$m[0]} = $m[1];
               	$env::debug and wlog "get_monitor_linear: dysk $m[0] limity $m[1]\n";
        }
	#
	# get name of disk interfaces from retreived buffer
	#
	foreach my $line (@buf) {
		#
		# split buffer
		# <device> <name>:<counts>...
		#
		my @a = split /\:/, $line, 2;
		#
		# if disk interface hasn't limit, create defaults
		#
		my @d = split / /, $a[0], 2;
		#
		# d[0] - device name
		# d[1] - mount name
		#		
		if (@d < 2) {		
			$env::debug and wlog "get_monitor_linear: ERROR: no space in $a[0] in line $line\n";
			next;
		} 
		if (! $disk{$d[1]}) {
			$disk{$d[1]} = "0 0";
			$jest_l = 1;
		}
		$cur_disk{$d[1]} = $a[1];		
	}
	#
	# if there isn't limit for interface, write new file with limits
	#
	if ($jest_l) {
		my $new_c = "";
                foreach my $k (sort keys %disk) {
                        $new_c .= "$k|$disk{$k}\n";
                }
                my $r = system("$main::cl trune_c \"$lim\" \"$new_c\"");
		$r >>= 8;
		$env::debug and wlog "get_monitor_linear: new config for $o_limit return $r\n";
	}
        
        #
        # get data for particual disk interface
        #	   
	foreach my $k (sort keys %disk) {		
                #
                # check, when last data was taken and also take historical data
                #
		my $ltime = 0;
		#
		# get thersholds
		#		
		my $fend = $k;		
		#
		# take limits
		#
		my ($l_size, $l_proc) = split / /,$disk{$fend}, 2;
		$fend =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
		if ($o_limit eq "disk") {
			#
			# if l_size exist make l_size as MegaBytes
			#
			if ($l_size > 0) { $l_size *= 1024 * 1024; }                
		}	
		 if ($o_limit eq "disk_inode") {
			$fend .= "-inode";
		}
		my @buf = get_file_v2($stime, $user, $monitor_id."/".$fend);
		my $wrong = 0;
		my $good = 0;
		#
		# analyze tail data for particular disk 
		#
		foreach my $l (sort @buf) {
			if ($l =~ /(\d{10})\s+(\d+)\s+(\d+)\s+(\d+)\s+([\w\d]+)/) {
				$ltime = $1;
				my $unit = $2;
				my $total = 1;
				($3 > 0) and $total = $3; 
				my $used = $4;					
				my $host = $5;
				#
				# if is set any limit (size or percent)
				#	
				if ((($l_size > 0) || ($l_proc > 0)) &&
				(($unit == -1) || 
				((($l_size > 0) && (($unit * $used) > $l_size)) || (($l_proc > 0) && (($used * 100) / $total) > $l_proc)))) {
		#	 		$env::debug and wlog "get_monitor_linear: PLAN ALARM dla $name $fend WRONG $wrong UNIT $unit USED $used TOTAL $total\n";
	
					$wrong or $wrong = $ltime; 
				} else {
					$wrong = 0;
					$good = $ltime;
				}
			}	
		}
	
		my $ldir = lday($user, $stime);
	
		my $unit = -1;
		my $total = 0;
		my $used = 0;
		my $send = 0;
                #
                # OUTPUT
                #
		if ($cur_disk{$k}) {
			$env::debug and wlog "get_monitor_linear: Current line for $k: $cur_disk{$k}\n";
			if ($cur_disk{$k} =~ /(\d+)\s+(\d+)\s+(\d+)/) {
			$env::debug and wlog "get_monitor_linear: new values $1 $2 $3\n";
				$unit = $1;
				$total = $2;
				$used = $3;
			}
		}

        my $sent = send_data_v2 ("$ldir/$monitor_id/$fend", "$stime $unit $total $used $main::hostname", 2);
		#
		# if tail of historical data is wrong 
		# we comment is as send always return 0 as send_data_v2 send data in background
		# if ($sent > 1) {
			
			my $comment;
			if ($o_limit eq "disk_inode") {
				$comment = "zajete $used z $total a limit $l_size i $l_proc \%";
			} else {
				$comment = "zajete ".int(($used * $unit) / (1024 * 1024))." MB z ".int(($total * $unit) / (1024 * 1024))." MB limit ".int($l_size / (1024 * 1024))." MB i $l_proc \%";
			}

			if ($wrong) {
				# one of two limits is set
				if ((($l_size > 0) || ($l_proc > 0)) &&
				# currently is problem too
				(($unit == -1) || ((($unit * $used) > $l_size) || ((($used * 100) / $total) > $l_proc) ))) {
				#
				# send alarm
				#
	                $env::debug and wlog "get_monitor_linear: ALARM dla $name $fend l_size $l_size l_proc $l_proc WRONG $wrong UNIT $unit USED $used TOTAL $total SENT $sent\n";
				
				    send_info("alarm", $user, $name, $monitor_id, 0, $o_limit, $wrong, $alarm_off, $comment, $k);
	             }
			} else {
				send_info("good", $user, $name, $monitor_id, 0, $o_limit, $good, $alarm_off, $comment, $k);
			}
		# }
		# print "get_monitor_linear: zapis $ldir/snmp/$name-$fend $stime $unit $total $used $main::hostname\n";
        }
}
#
# get network snmp information
# agrs:
# 1 - user
# 2 - name of system
# 3 - time
# 4 - file name with limits
# 5 - data taken from file (in format <name>:<statistics>)
#
sub get_monitor_grow 
{
	my ($user, $name, $monitor_id, $stime, $alarm_off, $o_limit, @buf) = @_;
	my (%net, %cur_net, $jest_l);
	$jest_l = 0;
	my $wrong = 0;
	my $good = 0;

	my $lim = $user."/monitor/".$monitor_id."/".$o_limit;

	$env::debug and wlog "get_monitor_grow: open file $lim\n";
	#
	# get limits
	#
	my ($r_ids, @plik) = ids_data_get ("get", $lim);
	($r_ids < 0) and return;
       	foreach my $n (@plik) {
       		chomp $n;
               	if ($n =~ /^#/) { next; }
               	my @m = split /\|/, $n, 2;
               	if (! $m[1]) { $env::debug and wlog "get_monitor_grow: brak limitow w $m[0]\n"; next; }
               	$net{$m[0]} = $m[1];
               	$env::debug and wlog "get_monitor_grow: siec $m[0] limity $m[1]\n";
        }
	#
	# get name of inerfaces
	# 
	#
	foreach my $line (@buf) {
		#$env::debug and wlog "get_monitor_grow: buf $line\n";
		# we need to catch last \: from line which is delimeter 
		# between interface name: data
		#
		if ($line =~  /(.+)\:(.+)/) {
			my $i_name = $1;
    			my $i_data = $2;

			#
			# if net interface hasn't limit, create defaults
			#
			$i_name =~ s/^\s+//;
			$i_name =~ s/\s+$//;
			# exist interface in IDS system
			if (! $net{$i_name}) {
				$net{$i_name} = "0 0";
				$jest_l = 1;
			}
			$cur_net{$i_name} = $i_data;
		}
	}
	#
	# if there isn't limit for interface, write new file with limits
	#
	if ($jest_l) {	
		my $new_c = "";
		foreach my $k (sort keys %net) {
			$new_c .= "$k|$net{$k}\n"; 
		}
		my $r = system("$main::cl trune_c \"$lim\" \"$new_c\"");
		$r >>= 8;
		$env::debug and wlog "get_monitor_grow: write new configuration with $r for $name-$o_limit\n";
	}
	
	
	#
	# get data for particual type
	#
	foreach my $k (sort keys %net) {	
		$env::debug and wlog "get_monitor_grow: key: $k\n";
		#
		# check, that we have all variables set
		#
		$cur_net{$k} or next;
		# $env::debug and wlog "get_monitor_grow: cur net is > $cur_net{$k} <\n";
		#
                # check, when last data was taken (also take historical data)
                #
		my $ltime = 0;
		#
		# get thersholds for net interface
		#
		
		my $fend = $k;
		my ($l_in, $l_out) = split / /,$net{$fend}, 2;
		#
		# if this is network
		#
		if ($o_limit eq "net") {
			#
			# if l_size exist make l_size as KiloBytes
			#
			if ($l_in > 0) { $l_in *= 1024; }
			if ($l_out > 0) { $l_out *= 1024; }
		}
	#	if ($o_limit eq "cpu") {
			#
			# if limit exist then multible by 100 Hz
			#
	#		if ($l_in > 0) { $l_in *= 100; }
               #         if ($l_out > 0) { $l_out *= 100; }
	#	}
		#
		# convert interface name
		#
		$fend =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
	
		my @buf = get_file_v2($stime, $user, $monitor_id."/".$fend);
		my ($o_in, $o_out, $o_time, $host, $i, $last_in, $last_out);
		$o_time = 0;
		$o_in = 0;
		$o_out = 0;
		$last_in = 0;
		$last_out = 0;
		$ltime = 0;
		$i = 0;
		foreach my $l (sort @buf) {
			if ($l =~ /(\d{10})\s+(\d+)\s+(\d+)\s+([\w\d]+)/) {
				($ltime == $1) and next;
				
				$o_time = $1 - $ltime;
				$ltime = $1;

				if ($2 > 0) {
					if ($2 >= $o_in) {
						$o_in = $2 - $last_in;
					} else {
						$o_in = 2**32 - $last_in + $2;
					}
				}
				if ($3 > 0) {
					if ($3 >= $o_out) {
						$o_out= $3 - $last_out;
					} else {
						$o_in = 2*32 - $last_out + $3;
					}
				}
				$last_in = $2;
                                $last_out = $3;
				$host = $4;
				#
				# if this are first data, don't analyse and go to next line to have correct data
				#	
				if (! $i) { $i++; next;}
				#
				# if there set any limit
				#
				my $si = int($o_in / $o_time);
				my $so = int($o_out / $o_time);
				# data from file are not correct
				if ((($2 == -1) && ($3 == -1)) ||
				# or data from file are higher than any limits
				((($l_in) && (($o_in / $o_time) > $l_in)) || 
				 (($l_out) && (($o_out / $o_time) > $l_out)))) {
					if (! $wrong) { $wrong = $ltime; }
				} else {
					$wrong = 0;
					$good = $ltime;
				}
				# $env::debug and wlog "get_monitor_grow: READ $k o_in $o_in o_out $o_out o_time $o_time l_in $l_in l_out $l_out si $si so $so ltime $ltime wrong $wrong\n";
			}	
		}
			
		my $ldir = lday($user, $stime);
		my ($r_in, $r_out);
		$r_in = 0;
		$r_out = 0;
		
		#
		# INPUT/ OUTPUT, get current data
		#
		if  (($o_limit eq "net") && 
			($cur_net{$k} =~ /(\d+)\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+(\d+)/))  {
                        $r_in = $1; 				# IN
                        $r_out = $2;				# OUT
		} 

	        if (($o_limit eq "cpu") && 
			($cur_net{$k} =~ /(\d+)\s+(\d+)\s+(\d+)\s+\d+\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/)) {
                        $r_in = $1 + $2; 			# USER: normal + niced
                        $r_out = $3 + $4 + $5 + $6; 		# KERNEL: system + iowait + irq + softirq
                }
		
		if (($o_limit eq "diskio")  &&
			($cur_net{$k} =~ /(\d+)\s+(\d+)/)) {
                        $r_in = $1;                             # IO reads 
                        $r_out = $2;                            # IO writes
		}				
		$o_time = $stime - $ltime;
        if (! $o_time) { 
            $env::debug and wlog "get_monitor_grow: o_time is 0 becuase stime: $stime ltime: $ltime\n";
            return 0;
        }
		$o_in = $r_in - $last_in;
		$o_out = $r_out - $last_out;

		#
		# OUTPUT
		#
	
		my $sent = send_data_v2 ("$ldir/$monitor_id/$fend",  "$stime $r_in $r_out $main::hostname", 2);
		# my $sent = 3;
		#
		# if set any limit
		#   # we comment is as send always return 0 as send_data_v2 send data in background

			# $env::debug and wlog "get_monitor_grow: #2: limity l_in $l_in l_out $l_out wrong $wrong o_in $o_in o_out $o_out o_time $o_time\n";
		# if ($sent > 1) {
			my $comment = "";

			if ($o_limit eq "cpu") {
                        	$comment = "wartości user: ".int($o_in/$o_time)." %% kernel: ".int($o_out/$o_time)." %%, progi user: $l_in %% kernel: $l_out %%";
                        } elsif ($o_limit eq "diskio") {
                        	$comment = "wartości odczyt: ".int($o_in/$o_time)." IO/s zapis: ".int($o_out/$o_time). " IO/s, progi odczyt: $l_in IO/s i zapis: $l_out IO/s";
                        } else {
                        	$comment = "wartości in: ".int($o_in/($o_time * 1024))." kB/s out: ".int($o_out/($o_time * 1024))." kB/s, progi in: ".($l_in / 1024)." kB/s i out: ".($l_out / 1024)." kB/s";
                        }

			if ($wrong)  {
				if ((($l_in) && (($o_in / $o_time) > $l_in)) || (($l_out) && (($o_out / $o_time) > $l_out))) {
				$env::debug and wlog "get_monitor_grow: ALARM dla $name $fend l_in $l_in l_out $l_out WRONG $wrong IN $o_in OUT $o_out\n";
	
				send_info("alarm", $user, $name, $monitor_id, 0, "$o_limit", $wrong, $alarm_off, $comment, $k);
				}
			} else {
				send_info("good", $user, $name, $monitor_id, 0, "$o_limit", $good, $alarm_off, $comment, $k);
			}
			
		# }
		# print "Do $ldir/snmp/$name-$fend $stime $r_in $r_out $main::hostname\n";
	}
}

sub initial {
        my $what = shift;
	
	$main::start_minute = int(time / $main::script_duration) * $main::script_duration;

        $main::www = 0;
        $main::mon_port = 0;
        $main::ping = 0;
        $main::login = 0;
	$main::poczta = 0;
        $main::dns = 0;
        $main::external = 0;
	$main::snmp = 0;
	$main::troute = 0;
        $main::protocol = "UNKNOWN";
        $main::configf = 0;

        if ($what =~/www.pl$/) {
                $main::protocol = "www";      
                $main::www = 1;
                $main::configf = "www";
        }
        if ($what =~/port.pl$/) {
                $main::protocol = "port";
                $main::mon_port = 1;
                $main::configf = "port";
        }
        if ($what =~/login.pl$/) {
                $main::protocol = "login";
                $main::login = 1;
                $main::configf = "login";
        }
        if ($what =~ /dns.pl$/) {
                $main::protocol = "DNS";
                $main::dns = 1;
                $main::configf = "dns";
        }
        if ($what =~ /external.pl$/) {
                $main::protocol = "external";
                $main::external = 1;
                $main::configf = "external";
        }
        if ($what =~/ping.pl$/) {
                $main::protocol = "icmp";
                $main::ping = 1;
                $main::configf = "ping";
        }
	if ($what =~/monitor.pl$/) {
                $main::protocol = "snmp";
                $main::snmp = 1;
                $main::configf = "monitor";
        }
	if ($what =~ /troute.pl$/) {
		$main::protocol = "troute";
		$main::troute= 1;
		$main::configf = "troute";
	}
	if ($what =~ /poczta.pl$/) {
                $main::protocol = "poczta";
                $main::poczta= 1;
                $main::configf = "poczta";
        }
        $main::dir = $what;
        $main::dir =~ s|scripts/+$main::configf.pl||;
        
        $main::cl = "$main::dir/netbone/bin/filec ";
        
        if ((!$main::www) && (!$main::mon_port) && (!$main::ping) && (! $main::snmp) && (! $main::poczta) &&
		(! $main::login) && (! $main::dns) && (! $main::external) &&(! $main::troute)) {
		# to test: (caller(0))[3];
                print "initial: Unable to determine name script (allowed: login.pl www.pl, ping.pl, port.pl, trace.pl dns.pl external.pl snmp.pl, poczta.pl), what $what\n";
                return 0;
       }
        if (! chdir $main::dir) {
	  	# $debug::main and wlog "initial: unable to chdir to $main::dir\n$!\n";
		print "initial: unable to chdir to what $what dir $main::dir\n$!\n";
		return 0;
	}
	return 1;
} 

#
# FUNCTIONS used by script
#

#
# in args
# 1 - start tinme in seconds
# 2 - user (with /konto prefix )
# 3 - name of adress
# 4 - rest, which consists from below:
# 5 - host we need connect to
# 6 - port on which we should connect to
# 7 - rest
# * address, which we should asked
# * text, which we should find on site
# out:
#  # 0 - good
# 1 - not good
#
 
sub get_www_v2 {
	 my ($stime, $user, $monitor_id ,$answer_time, $host, $http_proto, $port, $rest)  = @_;

	my $code = 1001;
	#
	# return line
	#
	my $r_line = "$stime ";
	my $err = "";
	#
        # make on which we directory should work
        #
        my $ldir = lday($user,$stime);
        #
        # construct name
        #
        my $lfile = "$ldir/$monitor_id";

	my ($address, $txt, $no_txt);
       #
       # <page:/login.php/><text:maciej browarski/text>
       #
       if ($rest =~ m|<page:(.+)/page>|) {
               $address = $1;
               $address =~ s/^\s+//;
               $address =~ s/\s+$//;
               $address =~ s/^https{0,1}:\/\///;
       }
	($rest =~ m|<text:(.+)/text>|) and $txt = $1;
	($rest =~ m|<no_text:(.+)/no_text>|) and $no_txt = $1;

	#
	# My WGET with timeout
	#
	my $time_out = $main::timeout - $main::timeout_ids;

	my $hst = Time::HiRes::time();
	my ($serwer, $page) = split /\//, $address, 2;
	$page or $page = '/';
	if ($answer_time) {
		my $ce =  int(($answer_time + 999)/1000);
                ($ce < $time_out) and $time_out = $ce;
	}

        $env::debug and wlog "get_www_v2: current time_out is $time_out as answer time is $answer_time\n";

	my ($r, $serwer_ip, @html) = send_http_v4($host, $time_out, $http_proto, $port, $page);	
	
	#
	# check, after get data, that we are still in our time
	#
	check_time_slot() and exit(1);	

	if (! $r) {
		$env::debug and wlog "get_www_v2: error with : $html[0]\n";
		$err = "$html[0] $serwer_ip";
		$err =~ s/ /_/g;
		$r_line .= "$main::timeout 1001 $main::hostname $err 0";
	} else {
		$env::debug and wlog "get_www_v2: $host done received data from $serwer_ip\n";

		my $het = sprintf ("%.3f", Time::HiRes::time() - $hst);
		($het < 0.001) and $het = "0.001";

		$het *= 1000;
			
		my $desc;
		my $size = 0;
		 my $moved = 0;

		# check is answer time is set
		# and is we are on time
		($answer_time and $env::debug) and wlog "get_www_v2: answer_time $answer_time het: ".($het * 1000)."\n";
		if ((! $answer_time) || ($het < $answer_time)) { 
			# set defaults errors
			if (! $txt) {
				# for page were we shouldn't parse text
				$desc = "Invalid response";
			} else {
				# for page where we should find text
				$desc = "no text found";
			}
			#
			# searching HTTP return code
			#
			my $n_txt_i = 0;
			#
			# save it to www page for review
			#
			my $s_f = "$env::faddr_local/tmp/$monitor_id";
			if (open FILE, " > $s_f") {
				print FILE @html;
				close FILE;
			} else {
				wlog "get_www_v2: unable to write tmp file to $s_f: $!\n";
			}
			#
			# parsing output
			#
			foreach my $l (@html) {
				 chomp $l;
				# $env::debug and wlog "get_www_v2: LINE $l\n";
				# wlog "get_www: LINE $l\n";
				# review HTTP header
				if (! $size) {
					# e.g.
					# HTTP/1.1 302 Found
					 if ($l =~ m|HTTP/1\.\d\s+(\d+)\s+([\w ]*)|) {
                                                $code = $1;
                                                $desc = $2;
                                                # $env::debug and wlog "FOR $host is code $code $desc NO TXT $no_txt TXT $txt\n";
						#
                                                # for page which are move
                                                # inform about error (as we should point to valid pages)
                                                #
                                                if (($code >= 300) && ($code < 310)) {
                                                        $desc = "Moved";
                                                } 

						#
						# even we received http header (which is good)
						# this still isn't success as we try to find txt
						# in body that we back code to 1001 and change error txt to below
						#
						if (($code == 200) && ($txt)) {
							$code = 1001;
							$desc = "Text not found";
						}
						

                                        } else {
						$desc = "Zły nagłówek HTTP: $l\n";
						last;
					}
				}
				$size += length($l);
				if (($code >= 300) && ($code < 310)) {
					if ($l =~ /^Location:\s+(\S+)/i) { 
						$moved = $1; 
						# when redirect found then then quit from this loop
						last;
					}
					next;
				}
				#
                                # text which should be on page has a priority
                                #

				if ($no_txt) {
					if ($l =~ /$no_txt/i)  { 
						$n_txt_i = 1;
						$code = 1001; 
						$desc = "błędny tekst od $size"; 
					}
				} 
				#
                                # try to find defined txt
                                #
				if (($txt) && (! $n_txt_i)) {
                                        if ($l =~ /$txt/i) { $code = 200; $desc = "tekst od $size"; }
				}
			}
		} else {
			$desc = "Required Time exceed";
		}
		$desc .= " $serwer_ip";
		$desc =~ s/ /_/g;
		$moved and $desc .= "_$moved";
		$r_line .= "$het $code $main::hostname $desc $size";
	}

	my $ret;

	if ($code == 200) {
		#
		# if not www_api then cache this information
		#
		if (! $main::www_api) {
			$ret = send_data_v2("$lfile", $r_line, 1);
		} else {
			$ret = send_data_v2("$lfile", $r_line, 0);
		}
		return (0, $ret);
	} else { 
		$ret = send_data_v2("$lfile", $r_line, 0);
		return (1, $ret); 
	}
	
}
#
# in args
# 1 - user (with /konto prefix )
# 2 - name of adress
# 3 - rest, which consists from below:
# 4 - DNS host we need connect ask  (more NS separated by comma)
# 5 - proto - protocol (dns)
# 6 - port
# 7 - rest
#   * name we asked
#   * answer
# out:
# array:
# n - return code (0-success, 1 failure)
# string - description
#

sub get_dns {
	my ($stime, $user, $monitor_id, $answer_time, $ns_ser, $proto, $port, $rest) = @_;

	my $ldir = lday($user, $stime);

	# my ($ns_ser, $proto, $addr, $resp) = split / /, $rest, 4;
	# <DNS_ask:ns1.browarski.net/><DNS_answer:91.228.197.101/>
       my @res_a;

       if ($rest =~ m|<DNS_answer:([\w\d\.\-\,]+)/>|) {
               @res_a = split /,/, $1;
         }

	my $addr = 0;
       if ($rest =~ m|<DNS_ask:([\w\d\.\-]+)/>|) {
               $addr = $1;
       }
       $addr or  return (1,"no proper address to ask");
       @res_a or  return (1,"no proper address for answer");

	my @ns_a = split /,/, $ns_ser;
	my $good = 0;
	my $r_line = "$stime ";

        #
        # construct name
        #
	my $lfile = "$ldir/$monitor_id";

#         my $lfile = "$ldir/$name-$proto";

	# require Net::DNS;

	my $res = Net::DNS::Resolver->new(
        nameservers => \@ns_a,
        recurse     => 1
        # debug       => 1
  	);
	my $hst = Time::HiRes::time();
	my $err = "";
	my $line = "";
	$env::debug and wlog ("get_dns: start\n");
	eval {
        	local $SIG{ALRM} = sub {
               		$env::debug and wlog "get_dns: ALARM pass dla $user $addr $main::timeout sec.\n";
                       	$err = "Timeout";
                       	die "Timeout";
                 };
                 alarm ($main::timeout - $main::timeout_ids);
		my $packet = $res->send($addr);
		foreach $a  ($packet->answer) {
			my @an = split /\s+/,$a->string;
			$env::debug and wlog ("get_dns: answer: $an[4]\n");
			if ($an[4] =~ /(\d+\.\d+\.\d+\.\d+)/) {
				my $ip = $1;
				foreach (@res_a) {
					$env::debug and wlog "get_dns: comp $_ to $ip\n";
					if ($_ eq $ip) { 
						$good++; 
						$line .= "$ip ";
					}
				}
			} else {
				$env::debug and wlog "get_dns: no IP address in: $a->string\n";
			}
			(@res_a == $good) and last;
		}
		$env::debug and wlog ("get_dns: addr $addr\n");
		alarm 0;
	};
	if ($@) {
        	$env::debug and wlog "get_dns: Time out with error: $@\n";
               	$err =~ s/ /_/g;
		my $timeout_t = ($main::timeout - $main::timeout_ids) * 1000;
               	$r_line .= "$timeout_t 1001 $main::hostname $err";
        } else {
        	$env::debug and wlog "get_dns: $addr done received data\n";

		my $het = sprintf ("%.3f", Time::HiRes::time() - $hst);
               	($het < 0.001) and $het = "0.001";
		  $het *= 1000;

               	
		$line =~ s/\s+$//;
		$line =~ s/ /_/g;
		if ((@res_a == $good) && ((! $answer_time) || ($het < $answer_time))) {
			$r_line .= "$het 0 $main::hostname $line";
		} else {
			 $r_line .= "$het 1001 $main::hostname brak_adresu_w_odpowiedzi";
		}
	
	}
	# my $ret = send_data ($lfile, $r_line);

        if (@res_a == $good) {
		my $ret = send_data_v2 ($lfile, $r_line, 1);
                return (0, $ret);
        } else {
		my $ret = send_data_v2 ($lfile, $r_line, 0);
                return (1, $ret);
        }


}
#
# in args
# 1 - user (with /konto prefix )
# 2 - name of adress
# 3 - rest, which consists from below:
# 4 - host we need connect to
# 5 - proto - protocol (smtp/pop3/pop3s/imap4)
# 6 - port on which we should connect to
# 7 - variable depend on monitor:
#   * user, which we should find on site
#   * password

# out:
# $code - 0 - success, 1 - failed
# $sent - to how many IDS information is send
#

#
# function which decide which sub funtion to run
# (odd minute )
#
sub get_poczta
{
	my ($stime, $user, $monitor_id, $answer_time,  $host, $proto, $port, $rest) = @_;
        my ($l_user, $l_pass);

        ($rest =~ m|<user:([\d\w\.]+)/>|) and $l_user = $1;
        ($rest =~ m|<password:([\S+]+)/password>|) and $l_pass = $1;
        if (! $l_user) {
               $env::debug and wlog "get_poczta: ERROR no user in rest: $rest\n";
               return 1;
        }
        if (! $l_pass) {
                $env::debug and wlog "get_poczta: ERROR no password in rest: $rest\n";
                return 1;
        
	}
	#
        # make on which we directory should work
        #
        my $ldir = lday($user,$stime);

        my $lfile = "$ldir/$monitor_id";

        my $code = 1001;
        #
        # return line
        #
        my $r_line = "$stime ";
        my $hst = Time::HiRes::time();

	if ($proto =~ /^SMTP/) {
	
		my ($ret, $err) = send_mail_verbose($proto, $port, "T3ST L4D0N1T E-MAIL: ".localtime(), "Test e-mail from LADONIT system, please do NOT delete it manually, it will be automatic delete by POP3/POP3S test", "$l_user\@$host");
		#
	        # check, that we are still in our time
	        #
	        check_time_slot() and exit(1);

        	if (! $ret) {
                        $env::debug and wlog "get_poczta: Time out with error: $@\n";
                        $err =~ s/ /_/g;
                        my $timeout_t = ($main::timeout - $main::timeout_ids) * 1000;

                        $r_line .= "$timeout_t 1001 $main::hostname $err";
                } else {
			$code = 0;
                        $env::debug and wlog "get_poczta: $host done received data\n";

                        my $het = sprintf ("%.3f", Time::HiRes::time() - $hst);
                        ($het < 0.001) and $het = "0.001";
                        $het *= 1000;

                        $err =~ s/ /_/g;
                        if ((! $answer_time) || ($het < $answer_time)) {
                                $r_line .= "$het $code $main::hostname $err";
                        } else {
                                $r_line .= "$het 1001 $main::hostname Required_Time_Exceed";
                        }
                }

		if ($ret) {
	                my $ret = send_data_v2 ($lfile, $r_line, 1);
	                return (0, $ret);
	        } else {
	                my $ret = send_data_v2 ($lfile, $r_line, 0);
	                return (1, $ret);
	        }
	} else {
		my $err;
		 my ($ret, $line);

		eval {
                	local $SIG{ALRM} = sub {
                        	$env::debug and wlog "get_poczta: ALARM pass dla $host $main::timeout sec.\n";
                                $err = "Timeout";
                                die;
                        };
                        alarm ($main::timeout - $main::timeout_ids);
			
			my @html;
                        my $hst = Time::HiRes::time();
			my $ok = "+OK";

			my $sock;
			if ($proto =~ /POP3S/) {
				$sock = IO::Socket::SSL->new(
                                	PeerHost => $host,
                                        PeerPort => $port,
                                        SSL_verify_mode => SSL_VERIFY_NONE
                                );

                                if (! defined ($sock)) {
                                	$env::debug and wlog "get_poczta: OPENSSL BLAD error=$!, ssl_error=$SSL_ERROR\n";
                                        $err = "OPENSSL ERROR=$!, SSL=$SSL_ERROR";
                                        die;
                                }
                                $env::debug and wlog "get_poczta: OPENSSL to $host $port $sock established\n";

			}
			if ($proto =~ /POP3$/) {
				#
				# receive e-mails by POP3
				#
			        my $af_inet     = 2;
			        my $pf_inet     = 2;
			        my $sock_stream = 1;
			
			        my $pro = getprotobyname('tcp');
			        my $iaddr = Socket::inet_aton($host);
				my $err;
					
		 		if (! $iaddr) {
					$err = "HOST_NOT_FOUND";
					die;
				}
	                	
	                	my $paddr = Socket::sockaddr_in($port, $iaddr);
	
	
	                        if (!(socket($sock, $pf_inet, $sock_stream, $pro))) {
	                                $env::debug and wlog "get_poczta: BLAD socket dla $host $!\n";
	                                $err = "get_poczta: socket: $!";
	                                alarm 0;
	                                die;
	                        }
	
	                        if (!(connect($sock, $paddr))) {
	                                $env::debug and wlog "get_poczta: BLAD connect dla $host $!\n";
	                                $err = "get_poczta: connect: $!";
	                                alarm 0;
	                                die;
	                        }
				$env::debug and wlog "get_poczta: NON secure to $host $port established\n";
			}

			if (! $sock) {
				$err = "Unkown protocol $proto";
				die;
			}
			#
			# POP3X Converstation
			#
	                ($ret, $line) = conv_v2($sock, $ok, "USER $l_user");
	                if ($ret) {
	                	$env::debug and wlog "get_poczta: BLAD USER dla $host $line\n";
	                	$err = "niespodziewana linia po logowaniu $line";
	                	alarm 0;
	                	die "get_poczta: unexecpected $line\n";
	                }
                        ($ret, $line) = conv_v2($sock, $ok, "PASS $l_pass");
                        if ($ret) {
                                $env::debug and wlog "get_poczta: BLAD LOGIN dla $host $line\n";
                                $err = "niespodziewana linia po user: $line";
                                alarm 0;
                                die "unexcpected $line\n";
                        }
			($ret, $line) = conv_v2($sock, $ok, "LIST");
                                if ($ret) {
                                        $env::debug and wlog "get_poczta: BLAD USER dla $host $line\n";
                                        $err = "niespodziewana linia po hasle $line";
                                        alarm 0;
                                        die "get_poczta: unexcpected $line\n";
                                }
			my $n = 0;
			#
			# get list of e-mails
			#
                                while (my $line = <$sock>) {
				if ($line =~ /^\./) { last; };
				if ($line =~ /\+OK\s+(\d+)\s+m/) { $n = $1; }
				$env::debug and wlog "get_poczta: $line";
			}
			$env::debug and wlog "get_login: waiting for $n messages\n";
			#
			# parse each e-mail and try do find ours
			# 
			my $i_del = 0;
			my $s = 1;
			#
			# parse only last 100 messages to find our test messages
			#
			($n > 100) and $s = $n - 100;

			for (my $i = $s;$i <= $n; $i++) {
				my $s =	syswrite $sock, "TOP $i\n";
				$env::debug and wlog "get_poczta: TOP $i\n";
				my $del = 0;
				LOOP: while (my $l = <$sock>) {
					$env::debug and wlog "get_poczta: $l";
					($l =~ /^subject:\s+T3ST L4D0N1T E-MAIL/i) and $del = 1;
					if ($l =~ /^\./) { last LOOP; };
				}
				if ($del) {
					$s = syswrite $sock, "DELE $i\n";
					my $l = <$sock>;
					if ($l =~ /^\+OK/) {
						$i_del++;
					} else {
						$env::debug and wlog "unexcpected answer when tried to deleted:$l\n";
						die "unexcpected answer when tried to deleted: $l\n";
					}
					$env::debug and wlog "get_poczta: DELE $i: $l";
				}
			}

                        $ret = syswrite $sock, "QUIT\n";
                        
                        my $end = <$sock>;
			if ($i_del) {
				$line .= " Deleletd $i_del message";
				($i_del > 1)  and $line .= "s";
			} else {
				$line .= " No messages has been deleted";
			}
                        $code = 0;
                        close $sock or blad "get_poczta: close: $!";
                        alarm 0;
                };
		#
	        # check, that we are still in our time
	        #
	        check_time_slot() and exit(1);
	
	        if ($@) {
	        	$env::debug and wlog "get_poczta: Time out with error: $@\n";
	                $err =~ s/ /_/g;
	                my $timeout_t = ($main::timeout - $main::timeout_ids) * 1000;
	
	                $r_line .= "$timeout_t 1001 $main::hostname $err";
	        } else {
	        	$env::debug and wlog "get_poczta: $host done received data\n";
	
	                my $het = sprintf ("%.3f", Time::HiRes::time() - $hst);
	                ($het < 0.001) and $het = "0.001";
	                $het *= 1000;
	
	                $line =~ s/ /_/g;
	                if ((! $answer_time) || ($het < $answer_time)) {
	                	$r_line .= "$het $code $main::hostname $line";
	                } else {
	                	$r_line .= "$het 1001 $main::hostname Required_Time_Exceed";
	                }
	        }
	
	
	        if (! $code) {
	                my $ret = send_data_v2 ($lfile, $r_line, 1);
	                return (0, $ret);
	        } else {
	                my $ret = send_data_v2 ($lfile, $r_line, 0);
	                return (1, $ret);
	        }
	}
}

#
# in args
# 1 - user (with /konto prefix )
# 2 - name of adress
# 3 - rest, which consists from below:
# 4 - host we need connect to
# 5 - proto - protocol (ftp/pop3/imap)
# 6 - port on which we should connect to
# 7 - variable depend on monitor:
#   * ftp user, which we should find on site
#   * ftp password 

# out:
# $code - 0 - success, 1 - failed
# $sent - to how many IDS information is send
# 
sub get_login {
	my ($stime, $user, $monitor_id, $answer_time,  $host, $proto, $port, $rest) = @_;
	my ($l_user, $l_pass);
	($rest =~ m|<user:([\d\w\.]+)/>|) and $l_user = $1;
	($rest =~ m|<password:([\S+]+)/password>|) and $l_pass = $1;
	if (! $l_user) {
               $env::debug and wlog "get_login: ERROR no user in rest: $rest\n";
               return 1;
	}
	if (! $l_pass) {
       		$env::debug and wlog "get_login: ERROR no password in rest: $rest\n";
                return 1;
         }
	
	my $code = 1001;
	#
	# return line
	#
	my $r_line = "$stime ";
	my $err = "";
	#
        # make on which we directory should work
        #
        my $ldir = lday($user,$stime);
        #
        # construct name
        #
	# require Socket;

	my $af_inet     = 2;
        my $pf_inet     = 2;
        my $sock_stream = 1;

    	my $lfile = "$ldir/$monitor_id";   
	my $pro = getprotobyname('tcp');
	my $iaddr = Socket::inet_aton($host);

	if ($iaddr) { 		
		#
		# My WGET for FTP with timeout
		#
		my @html;
		my $hst = Time::HiRes::time();
		my ($ret, $line);
		
		eval {
			local $SIG{ALRM} = sub {
				$env::debug and wlog "get_ftp: ALARM pass dla $host $main::timeout sec.\n";
				$err = "Timeout";
       	                	die "Timeout";
                	};
			alarm ($main::timeout - $main::timeout_ids);					
	
			my $paddr = Socket::sockaddr_in($port, $iaddr);	

			my $sock;
			my ($ok_1, $ok_2, $ok_3);
			if ($proto eq "FTP") {
				$ok_1 = "220";
				$ok_2 = "331";
				$ok_3 = "230";
			} else {
				$ok_1 = "+OK";
				$ok_2 = "+OK";
				$ok_3 = "+OK";
			}

			if (!(socket($sock, $pf_inet, $sock_stream, $pro))) {
				$env::debug and wlog "get_login: BLAD socket dla $host $!\n";
				$err = "get_login: socket: $!";
				alarm 0;
				die;
			}
			
			if (!(connect($sock, $paddr))) {
				$env::debug and wlog "get_login: BLAD connect dla $host $!\n";
				$err = "get_login: connect: $!";
				alarm 0;
				die; 
			}
			($ret, $line) = conv_v2($sock, $ok_1, "USER $l_user");
			if ($ret) {
				$env::debug and wlog "get_login: BLAD USER dla $host $line\n";
				$err = "niespodziewana linia po logowaniu $line";
				alarm 0;
				die "get_login: unexcpected $line\n";
			}
			($ret, $line) = conv_v2($sock, $ok_2, "PASS $l_pass");
			if ($ret) {
				$env::debug and wlog "get_login: BLAD LOGIN dla $host $line\n";
				$err = "niespodziewana linia po user: $line";
				alarm 0;
				die "unexcpected $line\n";
			}			
			($ret, $line) = conv_v2($sock, $ok_3, "QUIT");
			if ($ret) {
				$env::debug and wlog "get_login: BLAD USER dla $host $line\n";
				$err = "niespodziewana linia po hasle $line";
				alarm 0;
				die "get_login: unexcpected $line\n";
			}
			my $end = <$sock>;
			$code = 0;
			close $sock or blad "get_login: close: $!";
			alarm 0;
    		};

		#
		# check, that we are still in our time
		#
		check_time_slot() and exit(1);
		
		if ($@) {
			$env::debug and wlog "get_login: Time out with error: $@\n";
			$err =~ s/ /_/g;
			my $timeout_t = ($main::timeout - $main::timeout_ids) * 1000;

			$r_line .= "$timeout_t 1001 $main::hostname $err";
		} else {
			$env::debug and wlog "get_login: $host done received data\n";

			my $het = sprintf ("%.3f", Time::HiRes::time() - $hst);
			($het < 0.001) and $het = "0.001";
			$het *= 1000;
	
			$line =~ s/ /_/g;
			if ((! $answer_time) || ($het < $answer_time)) {
				$r_line .= "$het $code $main::hostname $line";
			} else {
				$r_line .= "$het 1001 $main::hostname Required_Time_Exceed";
			}
		}

	} else  {
		my $rtime = time - $stime;

                $err = "HOST_NOT_FOUND";
                $r_line .= "$rtime 1001 $main::hostname $err";
        } 

	if (! $code) {
		my $ret = send_data_v2 ($lfile, $r_line, 1);
		return (0, $ret);
	} else { 
		my $ret = send_data_v2 ($lfile, $r_line, 0);
		return (1, $ret); 
	}	
}

#
# Getting information from external script
# IN args
# 1 - stime - start time in secound
# 2 - user (with /konto/<user> )
# 3 - script name 
# 4 - script path 
# OUT args:
# 0|1 - good/bad
# n - number, to how many IDS information was sent
#

sub get_external {
	my ($stime, $user, $monitor_id, $answer_time, $rest) = @_;

	my $ldir = lday($user,$stime);
	my $lfile = "$ldir/$monitor_id";
	# my $lfile = "$ldir/$name-external";	
	my $duration = "0";
	my $s_name;
       ($rest =~ m|<script:([\w\d\.]+)/>|) and $s_name = $1;
       if (! $s_name) {
               $env::debug and wlog "get_external: ERROR no script in $rest\n";
               return (1,0);
       }
	my $code = 1001;
        #
        # return line
        #
        my $r_line = "$stime ";
        my $err = "";

	#
	# exec
	#	
	my $hst = Time::HiRes::time();
        my ($rc, $line);
	$rc = 1;

        eval {
        	local $SIG{ALRM} = sub {
               		$env::debug and wlog "get_external: ALARM pass dla $s_name $main::timeout sec.\n";
                       	$err = "Timeout";
                       	die "Timeout";
   		};
        	alarm ($main::timeout - $main::timeout_ids);
		my $exec;
		($s_name =~ /\.pl$/) and $exec = "$main::cl get \"$user/external/on-$s_name\" | /usr/bin/perl -w 2>&1";
                 
		($s_name =~ /\.sh$/) and $exec = "$main::cl get \"$user/external/on-$s_name\" | /bin/sh 2>&1";
                
		if ($exec) {
                        $env::debug and wlog "get_external: exec $exec\n";
                        my @lines = `$exec`;
			if (@lines) {
                        	$line = $lines[0];
			} else {
				$line = "No output";
			}
			chomp $line;
                        $code = $?;
                } else {
                        $env::debug and wlog "get_external: no sh or pl on end of $s_name\n";
                }
                alarm 0;
	};

	if ($@) {
       		$env::debug and wlog "get_external: Time out with error: $@\n";
                $err =~ s/\s+/_/g;
                $r_line .= "$main::timeout 1001 $main::hostname $err";
	} else {
        	$env::debug and wlog "get_external: $s_name done\n";

               my $het = sprintf ("%.3f", Time::HiRes::time() - $hst);
               ($het < 0.001) and $het = "0.001"; 
		$het *= 1000;

               $line =~ s/\s+/_/g;
		if ((! $answer_time) || ($duration < $answer_time)) {
	               $r_line .= "$het $code $main::hostname $line";
		} else {
			$r_line .= "$het $code $main::hostname Required_time_Exceed";
		}
        }
	$env::debug and wlog "get_external: zapis do $lfile r_line: $r_line\n";

        if (! $code) {
		my $ret = send_data_v2 ($lfile, $r_line, 1);
                return (0, $ret);
        } else {
		my $ret = send_data_v2 ($lfile, $r_line, 0);
                return (1, $ret);
        }

}
#
# Getting information from customers ping and port
# IN args
# 1 - stime - start time in secound
# 2 - user (with /konto/<user> )
# 3 - name of ping
# 4 - rest with:
# * hosts - list (separateed by comma)
# * proto - protocol (icmp, tcp, dup
# * number - port number
#
# OUT args:
# 0|1 - good/bad
# n - number, to how many IDS information was sent
#

sub get_ping_v2 {
	my ($stime, $user, $monitor_id , $answer_time,  $host, $proto, $number) = @_;
	my @errors;
	my $ldir = lday($user,$stime);
	my $lfile = "$ldir/$monitor_id";
	my $duration = "0";
	my @hosts = split /\s*,\s*/, $host;
	my $n_hosts = @hosts;
	#
	# count timeout based on numbers of hosts, which we need to ask
	#
 
	my $t_out = int (($main::timeout - $main::timeout_ids) / $n_hosts);
	
	if ($answer_time) {
                my $ce =  int(($answer_time + 999)/1000);
                ($ce < $t_out) and $t_out = $ce;
        }

	for (my $i = 0; $i < $n_hosts; $i++) {
		my $p; 
		#
		# my procedure for PING/PORT 
		#
		if ($proto =~ /icmp/i) {
                       $p = Net::Ping->new("icmp");
                       $p->source_verify(0);
               }
		
		if ($proto =~ /tcp/i) { 
			$p = Net::Ping->new("tcp");
			$p->port_number($number);
		}
		
		if ($proto =~ /udp/i) {
			$p = Net::Ping->new("udp",0);	
			$p->port_number($number);
		}
		#
		# no used
		#
		if ($proto =~ /syn/i) {		$p = Net::Ping->new("syn");	}
		
		if (!$p) { wlog "get_ping_v2: ERROR what is $proto ?\n"; return 0;}

		$p->hires();
		#
		# PING/PORT address
		#
		$env::debug and wlog "get_ping_v2: $i host: ".$hosts[$i]." set time out $t_out\n";
		my ($ret, $dura, $ip) = $p->ping($hosts[$i], $t_out);
		$p->close();	

		$duration = "0";
		((defined $dura) && ($dura > 0)) and $duration = sprintf("%.3f", $dura);	
		$duration *= 1000;
		
		check_time_slot() and exit(1);

		# 
		# if ok
		#
		if ($ret) {
			if ((! $answer_time) || ($duration < $answer_time)) { 
				my $re = send_data_v2 ($lfile, "$stime $duration 0 $main::hostname OK_$ip", 1); 
				$env::debug and wlog "get_ping_v2: ping for $host good done\n";
				return (0, $re);
			}
		}
		#		
		# get source IP who report error
                # then write it to error buffer
		# 
		my $out_l;
               if ($p->{"from_ip"}) {
                       my $d = "Timeout";
                       if (defined ($p->{"from_type"})) {
                               $d = "ICMP#".$p->{"from_type"};
				#
				# 0 mean OK, but as we here, mean
				# we are out of defined timeout
				# code described in:  /usr/include/netinet/ip_icmp.h
				#
				($p->{"from_type"} == 0) and $d = "DEFINED_TIMEOUT_REACHED";
                               ($p->{"from_type"} == 3) and $d = "UNREACHABLE";
				($p->{"from_type"} == 8) and $d = "PING_not_PONG?";
                               ($p->{"from_type"} == 11) and $d = "TIME_EXCEEDED";
                       }
			#
			# GW not show proper IP of GW <- TODO check why - currenlty need to be comment out
			#
                       # $out_l = $main::hostname."_$hosts[$i]_GW:".Socket::inet_ntoa($p->{"from_ip"})."_ERR:$d";
			$out_l = $main::hostname."_$hosts[$i]_ERR:$d";
               } else {
                       $out_l = $main::hostname."_$hosts[$i]_Timeout";
               }
               push @errors, $out_l;
		$env::debug and wlog "get_ping_v2: ERRORS: $out_l\n";
		# Timeout error
		#
		$env::debug and wlog "get_ping_v2: Time out for $hosts[$i] stat: $i/$n_hosts\n";
	}
	#
	# if any duration is set, then write it to log even this is timeout
	# this will give information what trigger give time out
	# is answer_time (ms < 1000) or timeout from alarm (ms > 1000)
	# 	
	($duration) and $t_out = $duration;
	my $out_l = "$stime $t_out 1001 $main::hostname ";
       if (@errors) {
               my $i = 0;
               foreach (@errors) {
                       $i++ and $out_l .= ":";
                       $out_l .= $_;
               }
       } else {
               $out_l = "Timeout";
       }
       my $re = send_data_v2($lfile, $out_l, 0);

	$env::debug and wlog "get_ping_v2: Time out with error: duration $duration\n";
	return (1, $re);
}

#
# Getting information from customers traceroute
# IN args
# 1 - stime - start time in secound
# 2 - user (with /konto/<user> )
# 3 - name of ping
# 4 - rest with:
# * hosts - list (separateed by comma)
# * proto - protocol (icmp, tcp, udp)
# * number - port number
#
# OUT args:
# 0|1 - good/bad
# n - number, to how many IDS information was sent
#


sub get_troute {
        my ($stime, $user, $monitor_id , $answer_time,  $host, $proto, $number) = @_;
        my @errors;
        my $ldir = lday($user,$stime);
        my $lfile = "$ldir/$monitor_id";
        my $duration = "0";
        my @hosts = split /\s*,\s*/, $host;
        my $n_hosts = @hosts;
	# max time in seconds for each TTL step for target host
	my $max = 2;
        #
        # count timeout based on numbers of hosts, which we need to ask
        #

        my $t_out = int (($main::timeout - $main::timeout_ids) / $n_hosts);

        if ($answer_time) {
                my $ce =  int(($answer_time + 999)/1000);
                ($ce < $t_out) and $t_out = $ce;
        }
	my $out_l;
	#
	# LOOP to check all asked hosts
	#
        for (my $i = 0; $i < $n_hosts; $i++) {

		my $s_duration = 0;
		#
		# loop for each host between us and target host
		#
		for (my $ttl = 1; $ttl < 30; $ttl++) {
	                my $p;
	                #
	                # my traceroute procedure
	                #
	                if ($proto =~ /icmp/i) {
	                       $p = Net::Ping->new("icmp", $max,0,0,0,$ttl);
	                       $p->source_verify(0);
	               }
	
	                if ($proto =~ /tcp/i) {
	                        $p = Net::Ping->new("tcp", $max,0,0,0, $ttl);
	                        $p->port_number($number);
	                }
	
	                if ($proto =~ /udp/i) {
	                        $p = Net::Ping->new("udp",0, $max, 0,0,0, $ttl);
	                        $p->port_number($number);
	                }
	                if (!$p) { wlog "get_troute: ERROR what is $proto ?\n"; return 0;}
	
	                $p->hires();
	                #
	                # PING/PORT address
	                #
			my $h_ip = inet_ntoa(inet_aton($hosts[$i]));
	                $env::debug and wlog "get_troute: $i ttl $ttl IP ".$h_ip." host: ".$hosts[$i]." set time out $t_out s\n";
	                my ($ret, $dura, $ip) = $p->ping($hosts[$i], $t_out);
	                $p->close();

	                $duration = "0";
	                ((defined $dura) && ($dura > 0)) and $duration = sprintf("%.3f", $dura);
	                $duration *= 1000;
			$s_duration += $duration;
	
	                check_time_slot() and goto get_troute_exit;
				
	                #
	                # if ok
	                #
	                if ($ret) {
	                        if ((! $answer_time) || ($duration < $answer_time)) {
	                                # my $re = send_data_v2 ($lfile, "$stime $duration 0 $main::hostname OK_$ip", 1);
					my $f = Socket::inet_ntoa($p->{"from_ip"});
	                                $env::debug and wlog "get_troute: trace for $host good done - from $f\n";
					push @errors, "Target_".$f."_".$duration."ms";
					# 
					# have we reach target host?
					#
					if ($f eq $h_ip) {
						# yes, exit from TTL loop
						$out_l = "$stime $s_duration 0 $main::hostname ";
						 if (@errors) {
        					       my $i = 0;
               						foreach (@errors) {
                       						$i++ and $out_l .= ":";
                       						$out_l .= $_;
               						}
       						}
						my $re = send_data_v2 ($lfile, $out_l, 1); 
						return (0, $re);
					}
					# nope, go next step in TTL loop
	        			next;
	                        }
	                }
	                #
	                # get source IP who report error
	                # then write it to error buffer
	                #
	               if ($p->{"from_ip"}) {
	                       my $d = "Timeout";
	                       if (defined ($p->{"from_type"})) {
	                               $d = "ICMP#".$p->{"from_type"};
	                                #
	                                # 0 mean OK, but as we here, mean
	                                # we are out of defined timeout
	                                # code described in:  /usr/include/netinet/ip_icmp.h
	                                #
	                                ($p->{"from_type"} == 0) and $d = "DEFINED_TIMEOUT_REACHED";
	                               ($p->{"from_type"} == 3) and $d = "UNREACHABLE";
	                                ($p->{"from_type"} == 8) and $d = "PING_not_PONG?";
					# TTL exeed - our target error which is success ;)
	                               if ($p->{"from_type"} == 11) {
						 my $f = Socket::inet_ntoa($p->{"from_ip"});
						if (($max * 1000) <= $duration) {
							push @errors,  "MAX_".$f."_".$max."s_reached";
						} else {
							push @errors,  "OK_".$f."_".$duration."ms";
						}
						next;
					}
	                       }
	                        #
	                        # GW not show proper IP of GW <- TODO check why - currenlty need to be comment out
	                        #
				push @errors,  "ERR_".Socket::inet_ntoa($p->{"from_ip"})."_$d";
	               } else {
	                       push @errors,  "ERR_Unknown_Timeout";
	               }
		}
              #  push @errors, $out_l;
              #  $env::debug and wlog "get_troute: ERRORS: $out_l\n";

                # Timeout error
                #
                $env::debug and wlog "get_troute: Time out for $hosts[$i] stat: $i/$n_hosts\n";
        }
get_troute_exit:
        #
        # if any duration is set, then write it to log even this is timeout
        # this will give information what trigger give time out
        # is answer_time (ms < 1000) or timeout from alarm (ms > 1000)
        #      
        ($duration) and $t_out = $duration;
        $out_l = "$stime $t_out 1001 $main::hostname ";
       if (@errors) {
               my $i = 0;
               foreach (@errors) {
			$env::debug and wlog "get_troute: error #".$i." -> ".$_."\n";
                       $i++ and $out_l .= ":";
                       $out_l .= $_;
               }
       } else {
               $out_l = "Timeout";
       }
	
       my $re = send_data_v2($lfile, $out_l, 0);

        $env::debug and wlog "get_troute: Time out with error: duration $duration\n";
        return (1, $re);
}

#
# function launch particular monitor
# IN:
# $user - user name
# $name - monitor's name
# $rest - rest from configurtion line
#
# OUT:
# 0 - action done - good result
# 1 - action done - bad result
# 2 - execute but ask_pref_ids global != pref_ids from cfg file
#
sub main_action {
	my ($user, $name, $rest) = @_;
	$env::debug and wlog "main_action: user $user name $name rest $rest\n";
        my $alarm_time = 5;
        my $check_time = 0;
        my $answer_time = 0;
        my $host = 0;
        my $proto = "NONE";
        my $port = 0;
	my $group = "0";
	my $alarm_off = 0;
	my $monitor_id = 0;
	#
	# parse all required parameters from rest line
	#
    ($rest =~ m|<alarm_time:(\d+)/>|) and $alarm_time = $1;
    ($rest =~ m|<good_time:(\d+)/>|) and $check_time = $1;
    ($rest =~ m|<response_time:(\d+)/>|) and $answer_time = $1;
    ($rest =~ m|<server:([\w\d\.\,\-]+)/>|) and $host = $1;
    ($rest =~ m|<protocol:(\w+)/>|) and $proto = $1;
    ($rest =~ m|<port:(\d+)/>|) and $port = $1;
	($rest =~ m|<group:(\d+)/>|) and $group = $1;
	($rest =~ m|<alarm_off:(\d+)/>|) and $alarm_off = $1;
	($rest =~ m|<monitor_id:([\w\d]+)/>|) and $monitor_id = $1;
	#
	# nprobes (2 from idscron, 1 from www when test button hit) probe, each $timeout (default 10s)
	#	
	my $ret = 1;
	for (my $probe = 0; $probe < $main::nprobes; $probe++) {
		$env::debug and wlog "PROBE $probe dla $user NAME \"$name\" REST $rest\n";
		my $r = 0;
		my $last_time = 0;
		#
		# start time
		#
		my $stime = time;
		#
		# last action time from log file
		#
		my $ctime = 0;
		#
		# test each monitor 
		#
		($r, $ctime, $last_time) = check_file_v3($stime, $user, $monitor_id);
		#
		# r:
		# 0 = no action is required, other script take it and is to early to 
		# take another actions
		#		
		$r or last;
		#
		# monitor action is required
		# r = 1 last data from log is success
		# r > 1 last data is wrong
		#
		my $code = 0;
                my $sent = 0;

		($main::www) and ($code, $sent) = get_www_v2($stime, $user,$monitor_id, $answer_time, $host, $proto, $port, $rest);
		($main::dns) and ($code, $sent) = get_dns($stime, $user, $monitor_id, $answer_time, $host, $proto, $port, $rest);
		($main::external) and ($code, $sent) = get_external($stime, $user, $monitor_id, $answer_time, $rest);
		# ping and port
		(($main::ping) || ($main::mon_port)) and ($code, $sent) = get_ping_v2($stime, $user, $monitor_id, $answer_time, $host, $proto, $port);
		($main::troute)  and ($code, $sent) = get_troute($stime, $user, $monitor_id, $answer_time, $host, $proto, $port);

		($main::login) and ($code, $sent) = get_login($stime, $user, $monitor_id, $answer_time, $host, $proto, $port, $rest);
		($main::poczta) and ($code, $sent) = get_poczta($stime, $user, $monitor_id, $answer_time, $host, $proto, $port, $rest);
	
		$env::debug and wlog "PROBE $probe dla $user $name code $code sent $sent r $r check_time $check_time ctime $ctime stime $stime alarm time $alarm_time alarm_off $alarm_off\n";
		#
		# ALARM section
		# code - 0 mean success
		# sent - how many IDS we updated
		#
		if (!$code) { 
			# 
			# ctime - when good has started
			# stime - current time
			# check_time -  good_time - inform about back system to good health in minutes
			# if sent good information to many IDSes
			# and from historical data also was good (but historical data not old than 1hour)
			# and check time is set
			# and check time and good zone is less than current time
			# try to send information, that system return from alarm (if such is set)
			#
			if (($sent > 1) && ($r == 1) ) {
				if ( ($check_time) && (($ctime + ($check_time * 60) - 5) < $stime) && ($last_time + 3600 > $stime) ) {
					#
		                        # TODO: add details to code, same code as below, we should rewrite to use funtion 
		                        #
		                        my $comment  = "host: $host";
		                        chomp $rest;
					if ($main::dns) { $comment .= " dla adresu $host"; }
		
		                        if ($main::www) { 
						my $page =  "/";
						($rest =~ m|<page:(.+)/page>|) and $page = $1; 
						$comment = lc($proto)."://$host:".$port." adres: $page"; 
					}
		                        if ($main::mon_port) { $comment .= " $proto:$port"; }
		
		                        if ($main::login) {
						# without polish letter because this goes to SMS
						my $l_user = "NONE";
						($rest =~ m|<user:([\d\w\.]+)/>|) and $l_user = $1;
		
		                                 $comment .= " protokol: $proto port: $port uzytkownik: $l_user";
		                        } 
			
					    send_info("good", $user, $name, $monitor_id, $group, $main::protocol, $ctime, $alarm_off, $comment);
					}
				#
				# 
				# check if alarm off not pass in hours
				# this remove old alarm, if problem still exist next execution should send again information about this alarm
				# but alarm_off (remind about old alarms) should be set
				#
				if ($alarm_off) {
					#
					# check is any alarm exists
					# NOTE: use list as this only for local IDS
					# we like make it as fast as possible
					# not require to ask all IDS for alarm file
					# as this is run all the time and alarm can be less than <5% of time
					#
					my ($jest, @data) = ids_data_get ("list", "$user/alarm-");
					
					foreach my $alarm_l (@data) {
						my $filen = "";
	
						if ($group) { $filen = "$group"; }
	                                        else { $filen = "$monitor_id"; }
	
						if ($alarm_l eq $filen) {
							my ($jest1, @data1) = ids_data_get ("get", "$user/alarm-$filen");
							#
							# if alarm file exist
							#
							if ($jest1) {
								#
								# alarm should be only in first line
                                                                #
                                                                my $eline = $data1[0];
								#
                                                                # isn't freeze so check is alarm pass
                                                                #
								if ((! ($eline =~ m|<action:freeze/>|)) && (check_pass_time($stime, $alarm_off, @data1))) {
									# if pass, then delete
									#
									my ($jest2, @data2) = ids_data_get("delete_c", "$user/alarm-$filen");
									$group and $eline .= "<group:$group/>";
									my $sent = send_data_v2 ("$user/history/alarms", "$eline<action_time:$stime/><action:alarm_off/>", 0);
									if ($sent < 2)  {
	                                					$env::debug and wlog "send_info: can't add alarm to history, write only to $sent IDS\n";
	                        					}
	
								}	
							}
						}
					}
				}
			}
			$ret = 0;
			last;
		} # if (!$code)
		#
		# if not success, and we have from file also signal that is not good on more that 2 IDSes
		# $r == 3 - failed and more script report it (check check_file_v3 what is number of required IDS - current: 2)
		# alarm_time - after what time we should sent alarm
		# ctime - first time, when failed started
		# stime - start tme
		# sent to how many IDS we send failed information
		#
		if (($r == 3) && (($ctime + ($alarm_time * 60) - 5) < $stime) && ($sent > 1)) {
			#
			# send alarm
			#
			my $comment = $host;
			chomp $rest;
			
			if ($main::dns) { $comment .= " dla adresu $host"; }
	
			if ($main::www) {
	                	my $page =  "/";
	                        ($rest =~ m|<page:(.+)/page>|) and $page = $1;
	                        $comment = lc($proto)."://$host:".$port." adres: $page";
	                }
			if ($main::mon_port) { $comment .= " $main::protocol:$port"; }
			if ($main::login) {
	            # without polish letter because this goes to SMS
	            my $l_user = "NONE";
	            ($rest =~ m|<user:([\d\w\.]+)/>|) and $l_user = $1;
	
	            $comment .= " protokol: $proto port: $port uzytkownik: $l_user";
	        }
						
			send_info("alarm", $user, $name, $monitor_id, $group, $main::protocol, $ctime, $alarm_off, $comment);
		}
					
		#
		# if this isn't last cycle
		#
		if ($probe < ($main::nprobes - 1))  {
			#
			# monitor return error, wait $timeout - time spent in function
			#
			my $rtime = time - $stime;
						
			if ($rtime < $main::timeout )  {
				$env::debug and wlog "MAIN: waiting...".($main::timeout - $rtime)."\n";
				sleep $main::timeout - $rtime;
			}
			$env::debug and wlog "MAIN: waiting...end\n";
	
			check_time_slot() and last;	

		}	
	}
	return $ret;
}

sub main_priority {
	my ($user, @plik) = @_;
	my %prio1;
        #
        # read configuration from file
        #
        foreach my $l (@plik) {
                chomp $l;
                #
                # ommit disabled
		#
                ($l =~/^#/) and next;
                my ($name, $rest) = split /\|/,$l,2;
                if (! $rest) {
                        $env::debug and wlog "main_priority: rest not defined in: $l\n";
                        next;
                }
		my $pref_ids = 0;

		#
	        # pass checks IDS running if this script is running for monitor support
       		# when this is run for monitor support IDS assigment doesn't work
        	# this is to send alarm for it
	        #
		($rest =~ m|<pref_ids:(\d+)/>|) and $pref_ids = $1;

	        if (! $main::ids_check) {
	                #
	                # if prefered IDS doesn't match ask_pref_ids
	                #
	                if ($main::ask_pref_ids != $pref_ids) {
	                	$env::debug and wlog "main_priority: ask_pref_ids ".$main::ask_pref_ids." but pref_ids is $pref_ids...skip\n";
	                        next;
	                }
	        }
	        $env::debug and wlog "main_priority: ask_pref_ids $main::ask_pref_ids pref_ids $pref_ids ids_check $main::ids_check\n";

                #
                # read active line
                # check priority
                #
                if ($rest =~ m|<priority:(\d+)/>|) {
                       my $p = $1;
                       $rest =~ s|<priority:\d+/>||;

                       my $i = "$p-$name";
                       $prio1{$i} = $rest;

               } else {
                        $env::debug and wlog "main_priority: first agument is not a number: $rest\n";
                }

        }
        # if empty hash, don't go further
        my $k = scalar keys %prio1;
        $k or return 0;
        #
        # create separate children for each user with parsed cfg file
        #
        my $pid_p = fork();
        if ($pid_p < 0) { blad "main_priority: cant user fork: $!\n"; }
	 my %prio = %prio1;

        if ($pid_p) {
                $env::debug and wlog "main_priority: child user $pid_p created for $user\n";
                $main::child_user{$pid_p} = 0;
                return $pid_p;
        }
        $env::debug and wlog "main_priority: for $user with ".$k." keys\n";
	#
	# trick with hash
	#
	my $cur_prio = 1;
	my %child;
	foreach my $l (sort keys %prio) {
		my ($p, $name) = split /\-/, $l,2;
		#
		# alarm_time - after what time sent alarm
		# after what time after alarm send good infromation
		# rest
		#
		#
       		# sort priority and names
       		#
                #    $ll = "$n|<priority:".$u[0]."/><alarm_time:".$u[1]."/><good_time:".$u[2]."/>";
                #                $ll .= "<response_time:".$u[3]."/><server:".$u[4]."/>";
		#
		my $rest = $prio{$l};
               my $good = 0;
               		
		if ($p != $cur_prio) {
			$env::debug and wlog "main_priority: change PRIO from $cur_prio to $p\n";
			$cur_prio = $p;
			# 
			# waiting for children
			#
			foreach my $c (keys %child) {
				$env::debug and wlog "main_priority: waiting for $c\n";
				my $kid = waitpid($c, 0);
				if ($kid) {
					$good = $?;
					$env::debug and wlog "child $kid return $?\n";
				}
				delete $child{$c};	
			}
		}	
		$env::debug and wlog "main_priority: name $name good $good response time\n";
		#
		# if there is any problem with higher priority don't go to current priority
		#
		$good and last;

		#
		# for each line from config file make child
		#
		my $pid = fork();
		if (! defined $pid) {
			$env::debug and wlog "main_priority: can't fork: $!\n";
			next;
		}
		if ($pid == 0) {
				exit main_action($user, $name, $rest);
		}
		if ($pid < 0) { blad "blad FORK: $!\n"; }
		if ($pid > 0) {
			$child{$pid} = 0;
			$env::debug and wlog "main_priority: pid $pid created\n";
		}
	}
	$env::debug and wlog "main_priority: waiting for low priority tasks\n";
	foreach my $c (keys %child) {
       		$env::debug and wlog "main_priority: waiting for $c\n";
       		my $kid = waitpid($c, 0);
       		if ($kid) {
       			$env::debug and wlog "main_priority: child $kid return $?\n";
        	}
               delete $child{$c};
	}
	#	
	# end of user fork()
	#
	return 0;
}
#
# DESC:
# get list of configurations files based on configf variable
# for each config file make fork and run main_priority (for simple) of snmp
# on end catch all children
#
# IN:
# global params need to be set (cfg_dir and configf)
#
sub user_loop {
        #
        # GET list of addresses
        #
        my ($r_ids, @user_file) = ids_data_get ("rist", "/$main::cfg_dir/$main::configf");
 
        my %child_user;
 
        #
        # MAIN LOOP
        #
        foreach my $l (@user_file) {
                chomp $l;
                #
                # only for particular user if argv[1] is set with this user
                #
                ($l =~ m|/konto/[\d\w\.]+/$main::cfg_dir/$main::configf|) or  next;
 
                my $user = $l;
                ($user =~ m|/$main::cfg_dir/$main::configf|) or next;
                $user =~ s|/$main::cfg_dir/$main::configf(\s*)$||;
 
                #
                # ommit account with prefix . (dot)
                #
                if ($user =~ /\/konto\/\./) {
                        $env::debug and wlog "user_loop: account $user start with . ommiting...\n";
                        next;
                }
		$env::debug and wlog "user_loop: file found: $l\n";
        	my $pid_p = fork();
		my $ll = $l;
                if ($pid_p < 0) {
                        $env::debug and wlog "user_loop: cant user fork: $!\n";
                        next;
                }
                if ($pid_p) {
                        $env::debug and wlog "user_loop: child user $pid_p created for $user\n";
                        $child_user{$pid_p} = 0;
                        next;
                }
 
                my @plik;
		#
		# get data for particaluar monitor
		# get /konto/<user>/cfg_dir/<port>
		#
        ($r_ids, @plik) = ids_data_get ("get", $ll);

		$env::debug and wlog "user_loop: exec $ll\n";
        #
        #  set languge per user
        #  
        set_language($user);

		if ($main::snmp) {
			exit main_snmp($user, @plik);
		} else {
                	exit main_priority($user, @plik);
		}
		
        }
        #
        # waiting for all USER children
        #
        foreach my $c (keys %child_user) {
                $env::debug and wlog "user_loop: waiting for USER: $c\n";
                my $kid = waitpid($c, 0);
                if ($kid) {
                        $env::debug and wlog "user_loop: child USER $kid return $?\n";
                }
                delete $child_user{$c};
        }
        $env::debug and wlog "user_loop: KONIEC\n";
}

sub user_one_action {
	my ($user, $na) = @_;
	$user = "/konto/".$user;
        chomp ($na);
        chomp($user);
        my $l = $user."/$main::cfg_dir/$main::configf";

        my ($r_ids, @plik) = ids_data_get ("get", "$l");
        my ($name, $rest);
        foreach my $l (@plik) {
                ($l =~ /^#/) and next;
                ($name, $rest) = split /\|/, $l, 2;
                if ($name eq $na) {
                        main_action($user, $name, $rest);
                        last;
                }
        }

}
return 1;
#
# Get snmp information
# 1 - user ( with /konto)
# 2 - name of server
# 3 - time
# 4 - function string (memory or disk)
# 5 - hash with data
#
sub get_snmp_data
{
	my ($user, $name, $stime, $fun, $t0) = @_;
	#
	# trick to get  hash
	#
	my %oid_ret = %$t0;
	my @ret;
        #
        # read information about all disk interfaces from server
        #
	my $oid;
	(($fun eq "disk") || ($fun eq "memory")) and $oid = ".1.3.6.1.2.1.25.2.3.1";
	($fun eq "net") and $oid = ".1.3.6.1.2.1.31.1.1.1";

	if (!$oid) {
		$env::debug and wlog "get_snmp_data: Function not set proper\n";
		return;
	}

        my (%ind, %name, %type, %unit, %total, %used, %disk);
	foreach my $l (keys %oid_ret) {
                chomp $l;
		my $ok = 0;
		my ($id, $rest);
		if (($fun eq "disk") || ($fun eq "memory")) {
                	if ($l =~ /$oid\.3.(\d+)/) {
                        	$id = $1;
                        	$rest = $oid_ret{$l};
                        	$rest =~ s/^\"//;
                        	$rest =~ s/\"$//;
				#
				# check type for disks
				#
				my $temp_oid = "$oid.2.$id";
				$ok = 0;
	                	if (defined $oid_ret{$temp_oid}) { 
					my $typ = $oid_ret{$temp_oid}; 
					#
					# disk - fixed storage
					#
	#				$env::debug and wlog "get_snmp_data: $fun - $typ - $id\n";
					if (($fun eq "disk") && ($typ eq ".1.3.6.1.2.1.25.2.1.4")) {
						$ok = 1;
					}
					if (($fun eq "memory") && (($typ eq ".1.3.6.1.2.1.25.2.1.2") || ($typ eq ".1.3.6.1.2.1.25.2.1.3"))) {
	                                        $ok = 1;
	                                }
				}
			}
		}
		if ($fun eq "net") {
                        if ($l =~ /$oid\.1.(\d+)/) {
				$id = $1;
                                $rest = $oid_ret{$l};
                                $rest =~ s/^\"//;
                                $rest =~ s/\"$//;
				$ok = 1;
			}
		}
	
                #
                # get index of disk interface 
                #
		if ($ok) {
			$disk{$rest} = 1;
                	$ind{$id} = $rest;                                           
		}
        }
        #
        # get data for particual interface
        #	   
	foreach my $k (sort keys %disk) {
		$k or next;
		$env::debug and wlog "get_disk_snmp: analizing: $k\n";
		#
		# take index
		#
		my $idx = -1;
		my $result = 0;

                foreach my $l (keys %ind) {
                        if ($k eq $ind{$l}) {
                                $idx = $l;
                                last;
                        }
                }
                if ($idx == -1) {
                        $env::debug and wlog "get_disk: NOT FOUND $k interface \n";
                        next;
                }
		my ($unit, $total, $used, $temp_oid);
		if (($fun eq "disk") || ($fun eq "memory")) {
			$temp_oid = "$oid.4.$idx";
			if (defined $oid_ret{$temp_oid}) { $unit = $oid_ret{$temp_oid}; $result++;}
	
			$temp_oid = "$oid.5.$idx";
			if (defined $oid_ret{$temp_oid}) { $total = $oid_ret{$temp_oid}; $result++; }
			#
			# no empty disks
			#
			# $total or next;	
			$temp_oid = "$oid.6.$idx";
	                if (defined $oid_ret{$temp_oid}) {$used = $oid_ret{$temp_oid}; $result++; }
	
	                #
	                # check OUTPUT is all data deliver 
	                #
			if ($result < 3) {
				$unit = -1;
				$total = 0;
				$used = 0;
			}
		
			push @ret, "/dev/null $k:$unit $total $used";
	                $env::debug and wlog "get_disk_snmp: IDX $ind{$idx}: UNIT $unit TOTAL $total USED $used\n";
       		}         
		if ($fun eq "net") {
                	my ($in_o, $in_oo, $out_o, $out_oo);

                	$temp_oid = "$oid.6.$idx";
                	if (defined $oid_ret{$temp_oid}) { $in_o = $oid_ret{$temp_oid}; $result++;}
			
			$temp_oid = "$oid.7.$idx";
                        if (defined $oid_ret{$temp_oid}) { $in_oo = $oid_ret{$temp_oid}; $result++;}

                	$temp_oid = "$oid.10.$idx";
                	if (defined $oid_ret{$temp_oid}) { $out_o = $oid_ret{$temp_oid}; $result++; }
			
			$temp_oid = "$oid.11.$idx";
                        if (defined $oid_ret{$temp_oid}) { $out_oo = $oid_ret{$temp_oid}; $result++; }


                	#
                	# OUTPUT
                	#
                	if ($result < 4) {
                        	$in_o = -1;
				$in_oo = -1;
                        	$out_o = -1;
				$out_oo = -1;
				
	                } 
			push @ret, "$k:$in_o $in_oo 0 0 0 0 0 0 $out_o $out_oo 0 0 0 0 0 0";
                        $env::debug and wlog "get_snmp_data: $k - $in_o $out_o\n";

		}
        }
	return @ret;
}
#
#
# Main function for snmp monitoring
#
# IN:
# $user - for who we do it
# @lines - cfg file for SNMP
#
sub main_snmp
{
	my ($user, @lines) = @_;
	my ($pr_auth, $pa_auth, $pr_pass, $pa_pass);
	#
	# CHILD
	#
	$env::debug and wlog "START for $user\n";
	my %child_system;
	#
	# parse configuration
	#
	foreach my $l (@lines) {
		#
		# omit comments
		#
		($l =~ /^#/) and next;
		#
		# take name of server
		#
		my ($name,$rest) = split /\|/,$l, 2;
		if (!$rest) { 
			$env::debug and wlog "brak rest\n"; 
			next; 
		}
		#
		# get technical server configuration 
		#
		$env::debug and wlog "Server name: $name\n";
		#
		# take protocol and check is it agent
		#
		# ns4|<server:ns4.cmit.net.pl/><protocol:snmp/><version:2c/><community:cmit/><port:16100/>

		my $protocol = "agent";
		($rest =~ m|<protocol:(\w+)/>|) and $protocol = $1;

		#
		# ommit agent data
		#
		($protocol eq "agent") and next;
		#
		# take data for SNMP connections
		#
		my ($ip, $version, $port, $comm, $monitor_id, $alarm_off);
		($rest =~ m|<version:([\w\d]+)/>|) and $version= $1;
		($rest =~ m|<server:([\w\d\.]+)/>|) and $ip= $1;
		($rest =~ m|<port:(\d+)/>|) and $port = $1;
		($rest =~ m|<community:([\w\.\d]+)/>|) and $comm= $1;
		($rest =~ m|<monitor_id:([\w\d]+)/>|) and $monitor_id = $1;
		($rest  =~ m|<alarm_off:([\d]+)/>|) and $alarm_off = $1;

		#
		# take net/disk/memory data from server by separate process
		#
		
		my $pid_s = fork();
		 if ($pid_s < 0) { blad "MAIN_SYSTEM: cant user fork: $!\n"; }
		if ($pid_s) {
			$env::debug and wlog "MAIN: child user $pid_s created for $user\n";
			$child_system{$pid_s} = 0;
			next;
		} 
		#
		# child for SNMP server
		#
		my $stime = time;
		$env::debug and wlog "ip: $ip version $version data $rest stime $stime\n";
		#
		# get required SNMP data from seerver
		#
		my  ($session, $error);
		#
		# prepare connections
		#
                if ($version eq "2c") {
                	($session, $error) = Net::SNMP->session (
                        	-hostname => "$ip",
                                -community => $comm,
                                -version      => 'snmpv2',
                                -port => $port,
                                -retries => 2,
                                -timeout => 2,
			);
                } elsif ($version eq "3") {
                        # ($rest =~ m|<level:(\w+)/>|) and $level = $1;
			$pr_auth = "";
			$pr_pass = "";
			$pa_pass = "";
			$pa_pass = "";
			# <server:192.168.2.3/><protocol:snmp/><version:3/><community:mantar/><port:161/><monitor_id:07f007106f05692de0d/><alarm_off:0/><auth_proto:MD5/><auth_pass:mantar123/auth_pass>
                        ($rest =~ m|<auth_proto:([\w\d]+)/>|) and $pr_auth= $1;
                        ($rest =~ m|<auth_pass:(.+)/auth_pass>|) and $pa_auth= $1;
                        ($rest =~ m|<enc_proto:(\w+)/>|) and $pr_pass = $1;
                        ($rest =~ m|<enc_pass:(.+)/enc_pass>|) and $pa_pass = $1;
			$env::debug and wlog "community $comm auth_proto $pr_auth auth_pass $pa_auth REST $rest\n";	
			($session, $error) = Net::SNMP->session (
                       		-hostname => "$ip",
                                -user => "$comm",
                                -version      => 'snmpv3',
                                -port => $port,
                                -retries => 2,
                                -timeout => 2,
				-authprotocol => $pr_auth,
				-authpassword => $pa_auth,
				-privprotocol => $pr_pass,
				-privpassword => $pa_pass,
			);
		} else {
                	$env::debug and wlog "MAIN: unknown version $version\n";
                        exit 1;
                }
                if (!defined $session) {
                	$env::debug and wlog "MAIN: error $error with session\n";
                        exit 1;
                }

		my %oid_ret;
		my @oidy;
		# memory and disks OID
		push @oidy, ".1.3.6.1.2.1.25.2.3.1";
		# network 64bits OID
		push @oidy, ".1.3.6.1.2.1.31.1.1.1";
		#
		# get all data at once for speed
		#
		foreach my $oid (@oidy) {
			# $env::debug and wlog "MAIN: READ $oid\n";
                 	my @args =  ( -varbindlist    => [ $oid ]);
                	push(@args, -maxrepetitions => 25);
                	outside: 
			while (defined($session->get_bulk_request(@args))) {
	                	my @oids = oid_lex_sort(keys(%{$session->var_bind_list()}));

       	                 	foreach (@oids) {
                                	oid_base_match($oid, $_) or last outside;

                                	my $l = sprintf ( "%s %s", $_, $session->var_bind_list()->{$_});
                                	$oid_ret{$_} = $session->var_bind_list()->{$_};
                                	# $env::debug and wlog "MAIN: $l\n";
               	         		# Make sure we have not hit the end of the MIB
                        		if ($session->var_bind_list()->{$_} eq 'endOfMibView') { last outer; }
                		}
      				# Get the last OBJECT IDENTIFIER in the returned list
                		@args = (-maxrepetitions => 25, -varbindlist => [pop(@oids)]);
			}
        	}

		#
                # get network, memory and disks names  as SNMP can support only this
                #
		#
		# parse data
		#
		my @ex = ("net", "disk", "memory");
		foreach my $fun (sort @ex) {
			my (%disk, @buf);
			#
			# save data to IDS
			#
			$env::debug and wlog "MAIN: GO with $fun\n";
                        my @data = get_snmp_data($user, $name, $stime, $fun, \%oid_ret);
			
			if (@data) {
				if (($fun eq "disk") || ($fun eq "memory")) {
					get_monitor_linear($user, $name, $monitor_id, $stime, $alarm_off, $fun, @data);  
				}
				if ($fun eq "net") {
                                        get_monitor_grow($user, $name, $monitor_id, $stime, $alarm_off, $fun, @data);
                                } 
			} else {
                        	$env::debug and wlog "MAIN: no data found for $fun and $name\n";
			}
		}
		#
		# exit from child
		#
		exit;
	}
	#
	# catch all child system
	# 
	foreach my $c (keys %child_system) {
		$env::debug and wlog "MAIN: waiting for SYSTEM: $c\n";
		my $kid = waitpid($c, 0);
		if ($kid) {
			$env::debug and wlog "MAIN: child SYSTEM $kid return $?\n";	
		}	
		delete $child_system{$c};
	}
		
}

sub open_pipe 
{
    my $pipe_name = shift;
    if (! -p $pipe_name) {
        $env::debug and wlog "$pipe_name doesn't exist or isn't pipe\n";
               return (-1);
       }

    my $p;
    my $ret = sysopen $p, $pipe_name, O_RDONLY;
    if (! $ret) {
        # $env::debug and wlog "can not open pipe $pipe_name $!\n";
        return -1;
    }
    return $p;
}
sub reopen_pipe 
{
     my $pipe_name = shift;
    my $i = 0;
    my $pipe;
    for (;;) {
            $pipe =  open_pipe($pipe_name);
            if ($pipe == -1) {
                    $env::debug and wlog "error in pipe:$!\n";
                    if ($i > 3) { sleep 1; }
                    if ($i > 9) {
                            $env::debug and wlog "error in 9th time pipe:$!\n";
                            exit (-1);
                    }
                    $i++;

                    next;
            }
        last;
    }
    $env::debug and wlog "reopen_pipe: success open pipe\n";
    return $pipe;
}

sub create_pipe
{
     my $pipe_name = shift;
    my $m = umask 0000;
    if (! POSIX::mkfifo($pipe_name, 0777)) {
        $env::debug and wlog "unable to create fifo: $!\n";
        exit (-1);
    }
    umask $m;
}

