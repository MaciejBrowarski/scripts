#
# scripts create symlinks
#
# 1.0 2017 Feb - add trace
# 1.1 2017 Nov - add poczta
#
LN=/bin/ln

ver:
	  ../scripts_admin/scripts.pl version

all:
	for NAME in poczta.pl poczta_check.pl poczta_pref.pl troute.pl troute_check.pl troute_pref.pl login_check.pl login_pref.pl dns.pl dns_check.pl dns_pref.pl external.pl external_check.pl external_pref.pl ping.pl ping_check.pl ping_pref.pl port.pl port_check.pl port_pref.pl www.pl www_check.pl www_pref.pl ; \
	do \
	if [ -L $$NAME ]; then \
		echo $$NAME - "exists - deleting.." \
		/bin/rm $$NAME;\
	fi ; \
	$(LN) -fs login.pl $$NAME;\
	done



