package language; 
our %polski;
our %english;
#
# common 
#
$polski{'hello'} = "Witaj";
$english{'hello'} = "Dear";

$english{'footer_cmit'} = "<br>Best Regards,<br><i>CMIT Team</i></br>";
$polski{'footer_cmit'} = "<br>Pozdrawiamy,<br><i>Zespół CMIT</i></br>";
#
# follow are tranlsation for deticated scripts
#
$polski{'report_0'} = "Strona";
$polski{'report_1'} = "Urządzenie";
$polski{'report_2'} = "Port UDP";
$polski{'report_3'} = "Port TCP";
$polski{'report_4'} = "Autentykacja FTP";
$polski{'report_5'} = "Autentykacja POP3";
$polski{'report_6'} = "Serwis DNS";
$polski{'report_7'} = "Skrypt";
$polski{'report_8'} = "Trasa";

$polski{'report_10'} = "Pamieć";
$polski{'report_11'} = "Dysk";
$polski{'report_12'} = "Karta sieciowa";
$polski{'report_13'} = "Procesor";
$polski{'report_14'} = "I/O dysku";
$polski{'report_15'} = "I-node";


$polski{'report_19'} = "niedostępne";
$polski{'report_20'} = "Monitor";
$polski{'report_21'} = "Serwer";
$polski{'report_22'} = "Urządzenie";

$polski{'report_30'} = "Poniżej znajduje się %s raport dostępności z monitorowanych systemów";
$polski{'report_31'} = "W załączniku znajduję się log z monitorowanych systemów";
$polski{'report_32'} = "W razie jakichkolwiek wątpliwości, prosimy o kontakt";

$polski{'report_40'} = "codzienny";
$polski{'report_41'} = "tygodniowy";
$polski{'report_42'} = "miesięczny";
#
# below is for topic, so special characters need to be used
#
$polski{'report_50'} = "raport_dost=EApno=B6ci_z_systemu_CMIT";
$english{'report_50'} = "accessiblity_report_from_CMIT_system";

$english{'report_0'} = "Page";
$english{'report_1'} = "Device";
$english{'report_2'} = "UDP port";
$english{'report_3'} = "TCP port";
$english{'report_4'} = "FTP authentication";
$english{'report_5'} = "POP3 authentication";
$english{'report_6'} = "DNS service";
$english{'report_7'} = "Script";
$english{'report_8'} = "Route";


$english{'report_10'} = "Memory";
$english{'report_11'} = "Disc";
$english{'report_12'} = "Network card";
$english{'report_13'} = "Processor";
$english{'report_14'} = "disk I/O";
$english{'report_15'} = "I-node";

$english{'report_19'} = "unavailable";
$english{'report_20'} = "Monitor";
$english{'report_21'} = "Server";
$english{'report_22'} = "Device";

$english{'report_30'} = "Below you can find a %s accessibility report from your systems";
$english{'report_31'} = "In attachment you can find log from monitoring systems";
$english{'report_32'} = "If you have any questions or doubts please don't hesitate to contact us";

$english{'report_40'} = "daily";
$english{'report_41'} = "weekly";
$english{'report_42'} = "monthly";


$polski{'calendar'}{'0'} = "styczeń";
$polski{'calendar'}{'1'} = "luty";
$polski{'calendar'}{'2'} = "marzec";
$polski{'calendar'}{'3'} = "kwiecień";
$polski{'calendar'}{'4'} = "maj";
$polski{'calendar'}{'5'} = "czerwiec";
$polski{'calendar'}{'6'} = "lipiec";
$polski{'calendar'}{'7'} = "sierpień";
$polski{'calendar'}{'8'} = "wrzesień";
$polski{'calendar'}{'9'} = "październik";
$polski{'calendar'}{'10'} = "listopad";
$polski{'calendar'}{'11'} = "grudzień";

$english{'calendar'}{'0'} = "January";
$english{'calendar'}{'1'} = "February";
$english{'calendar'}{'2'} = "March"; 
$english{'calendar'}{'3'} = "April";
$english{'calendar'}{'4'} = "May";
$english{'calendar'}{'5'} = "June";
$english{'calendar'}{'6'} = "July";
$english{'calendar'}{'7'} = "August";
$english{'calendar'}{'8'} = "September";
$english{'calendar'}{'9'} = "October";
$english{'calendar'}{'10'} = "November";
$english{'calendar'}{'11'} = "December";


$polski{'send_info_1'} = "Problem z hostem o nazwie";
$polski{'send_info_2'} = "Problem z portem o nazwie";
$polski{'send_info_3'} = "Problem ze skryptem o nazwie";
$polski{'send_info_4'} = "Problem ze stroną o nazwie";
$polski{'send_info_5'} = "Problem z DNSem o nazwie";
$polski{'send_info_6'} = "Problem z autoryzacją o nazwie";
$polski{'send_info_7'} = "Problem z trasą";
$polski{'send_info_8'} = "Problem z pocztą";

$polski{'send_info_10'} = "Problem z pojemnością na dysku %s na serwerze o nazwie %s";
$polski{'send_info_11'} = "Problem z kartą sieciową %s na serwerze o nazwie %s";
$polski{'send_info_12'} = "Problem z pamiecią %s na serwerze o nazwie %s";
$polski{'send_info_13'} = "Problem z obciążęniem procesora %s w serwerze o nazwie %s";
$polski{'send_info_14'} = "Problem z IO %s na serwerze o nazwie %s";
$polski{'send_info_15'} = "Problem z ilością inode na %s na serwerze o nazwie %s";

$polski{'send_info_20'} = "Alarm dla";
$polski{'send_info_21'} = "Początek od";
$polski{'send_info_24'} = "Koniec alarm dla";

$polski{'send_info_51'} = "Host o nazwie %s znowu widoczny";
$polski{'send_info_52'} = "Port o nazwie %s znowu widoczny";
$polski{'send_info_53'} = "Skrypt o nazwie %s znowu działa";
$polski{'send_info_54'} = "Strona o nazwie %s znowu widoczna";
$polski{'send_info_55'} = "DNS o nazwie %s znowu działa";
$polski{'send_info_56'} = "Autoryzacja o nazwie %s znowu działa";
$polski{'send_info_57'} = "Trasa o nazwie %s znowu działa";
$polski{'send_info_58'} = "Poczta o nazwie %s znowu działa";


$polski{'send_info_60'} = "Zajetość dysku %s na serwerze o nazwie %s poniżej progu";
$polski{'send_info_61'} = "Karta sieciowa %s na serwerze o nazwie %s przesyła dane poniżej progu";
$polski{'send_info_62'} = "Pamieć %s na serwerze o nazwie %s ponizej progu";
$polski{'send_info_63'} = "Zajetość procesora %s na serwerze o nazwie %s poniżej progu";
$polski{'send_info_64'} = "IO %s na serwerze %s poniżej progu";
$polski{'send_info_65'} = "inode %s na serwerze %s poniżej progu";

$polski{'send_info_100'} = "Problem z agentem na serwerze";
$polski{'send_info_101'} = "Niezidentyfikowany błąd %s na serwerze %s. Proszę o kontakt z administratorami CMIT";


$english{'send_info_1'} = "Problem with host";
$english{'send_info_2'} = "Problem with port";
$english{'send_info_3'} = "Problem with script";
$english{'send_info_4'} = "Problem with www page";
$english{'send_info_5'} = "Problem with DNS";
$english{'send_info_6'} = "Problem with authorization";
$english{'send_info_7'} = "Problem with trace";
$english{'send_info_8'} = "Problem with mail";


$english{'send_info_10'} = "Problem with %s disk on %s server";
$english{'send_info_11'} = "Problem with %s network card on %s server";
$english{'send_info_12'} = "Problem with %s memory on %s server";
$english{'send_info_13'} = "Problem with load on %s cpu on %s server";
$english{'send_info_14'} = "Problem with IO %s on %s server";
$english{'send_info_15'} = "Problem with inode on %s on %s server";

$english{'send_info_20'} = "Alarm for";
$english{'send_info_21'} = "It has started since";
$english{'send_info_24'} = "Alarm end for";

$english{'send_info_51'} = "Host %s is visible again";
$english{'send_info_52'} = "Port %s is visible again";
$english{'send_info_53'} = "Script %s is working again";
$english{'send_info_54'} = "Page %s is visible again";
$english{'send_info_55'} = "DNS %s is working again";
$english{'send_info_56'} = "Authorization %s is working again";
$english{'send_info_57'} = "Trace %s is working again";
$english{'send_info_58'} = "Mail %s is working again";

$english{'send_info_60'} = "Free space on %s disk on %s server above the limit";
$english{'send_info_61'} = "Network card %s on %s server %s is sending data below the limit";
$english{'send_info_62'} = "%s memory on %s server is now below the limit";
$english{'send_info_63'} = "Load on %s CPU on %s server is now below the limit";
$english{'send_info_64'} = "IO %s on %s server is now below the limit";
$english{'send_info_65'} = "inode %s on %s server is now below the limit";

$english{'send_info_100'} = "Problem with agent on server";
$english{'send_info_101'} = "Unidentified %s error on %s server. Please contact with CMIT administrators";


