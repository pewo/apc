#!/usr/bin/perl -w

use strict;
use Data::Dumper;
use Net::SNMP;

use Getopt::Long;

#####################################################################
# From the apc mib
#####################################################################
# SYNTAX        INTEGER  {       
#               immediateOn     (1),     
#               immediateOff    (2),     
#               immediateReboot         (3),     
#               outletUnknown   (4),     
#               delayedOn       (5),     
#               delayedOff      (6),     
#               delayedReboot   (7),     
#               cancelPendingCommand    (8)      
#       }
#       ACCESS  read-write       
#       DESCRIPTION              
#       "Getting this variable will return the outlet state. If
# the outlet is on, the immediateOn (1) value will be returned.
# If the outlet is off, the immediateOff (2) value will be
# returned. If the state of the outlet cannot be
# determined, the outletUnknown (4) value will be returned.
# If the outletUnknown condition should occur, all devices
# powered by the PDU should be shut down. The PDU's power
# should then be cycled to clear this condition.
# 
# Setting this variable to immediateOn (1) will immediately turn
# the outlet on.
# 
# Setting this variable to immediateOff (2) will immediately turn
# the outlet off.
# 
# Setting this variable to immediateReboot (3) will cause the
# Switched Rack PDU to perform an immediateOff command, wait the
# rPDU2OutletSwitchedConfigRebootDuration OID time, and then perform an
# immediateOn command.
# 
# Setting this variable to delayedOn (5) will turn the outlet on
# after the rPDU2OutletSwitchedConfigPowerOnTime OID time has elapsed.
# 
# Setting this variable to delayedOff (6) will turn the outlet off
# after the rPDU2OutletSwitchedConfigPowerOffTime OID time has elapsed.
# 
# Setting this variable to delayedReboot (7) will cause the
# Switched Rack PDU to perform a delayedOff command, wait the
# rPDU2OutletSwitchedConfigRebootDuration OID time, and then perform a
# delayedOn command.
# 
# Setting this variable to cancelPendingCommand (8) will cause any
# pending command to this outlet to be cancelled."
#####################################################################


my($prod) = "1.3.6.1.4.1.318.1.1.4.1.4";
# rPDU2OutletSwitchedControlCommand
my($commandoid) = "1.3.6.1.4.1.318.1.1.26.9.2.4.1.5";

sub lastoidindex($) {
	my($val) = shift;
	my($res) = undef;
	if ( $val ) {
		my(@arr) = split(/\./,$val);
		$res = $arr[-1];
	}
	return($res);
}

sub getoutlets($) {
	my($session) = shift;
	my($result);

	$result = $session->get_table( -baseoid => $commandoid,);

	if ( $session->error() ) {
		die "error: " . $session->error() . "\n";
	}

	my(%outlets) = ();
	my(%status) = ();
	foreach ( sort keys %$result ) {
		my($outlet) = lastoidindex($_);
		$outlets{$outlet}{oid}=$_;
		$outlets{$outlet}{status}=$result->{$_};
	}

	return(%outlets);
}

sub getinfo($) {
	my($session) = shift;
	my($result);

	my($baseoid) = "1.3.6.1.4.1.318.1.1.26.2";
	my(%oids) = (
		$baseoid . ".1.3.1" => "Name" ,
		$baseoid . ".1.4.1" => "Location" ,
  	  	$baseoid . ".1.5.1" => "HardwareRev" ,
  	  	$baseoid . ".1.6.1" => "FirmwareRev" ,
  	  	$baseoid . ".1.8.1" => "ModelNumber" ,
  	  	$baseoid . ".1.9.1" => "SerialNumber" ,
	);
	$result = $session->get_table ( -baseoid => $baseoid, );
	if ( $session->error() ) {
		die "error: " . $session->error() . "\n";
	}

	my($oid);
	my(%res);
	foreach $oid ( sort keys %$result ) {
		my($name) = $oids{$oid};
		if ( $name ) {
			$res{$name}=$result->{$oid};
		}
	}

	return(%res);
}
	

my $onoutlet = 0;
my $command = undef;
my $check = undef;
my $perf = undef;
my $info = undef;
my $community = "private";
my $hostname = undef;
my $verbose = undef;
my $help = undef;

GetOptions(
	"outlet=i" => \$onoutlet, 
	"command=s" => \$command,
	"hostname=s" => \$hostname,
	"verbose"  => \$verbose,
	"check"  => \$check,
	"info"  => \$info,
	"perf"  => \$perf,
	"help"  => \$help,
) or die("Error in command line arguments\n");

my(%command) = (
	immediateon => 1,
	immediateoff => 2,
	immediatereboot => 3,
	outletunknown => 4,
	delayedon => 5,
	delayedoff => 6,
	delayedreboot => 7,
	cancelpendingcommand => 8,
);

my(%revcommand) = ();
while( my($key,$value) = each(%command) ) {
	$revcommand{$value}=$key;
}
my($showhelp) = 0;

unless ( $hostname ) {
	print "Missing hostname\n";
	$showhelp++;
}

my($commandid) = undef;
if ( $command ) {
	$commandid = $command{lc($command)};
	unless ( defined($commandid) ) {
		print "Unknown command $command\n";
		$showhelp++;
	}
}

if ( $help || $showhelp) {
	print "\n";
	print "Usage: $0\n";
	print "  --outlet=<i>  ( which outlet to operate on, use 0(default) to operate on all )\n";
	print "  --hostname=<hostname or ip>\n";
	print "  --verbose  ( print some verbose output )\n";
	print "  --help ( print this help )\n";
	print "  --check ( check if an outlet has status of --command )\n";
	print "  --perf ( include performance output on check )\n";
	print "  --info ( print som info about --hostname )\n";
	print "  --command=<command from mib>\n";
	print "            immediateOn\n";
	print "            immediateOff\n";
	print "            immediateReboot\n";
	print "            outletUnknown\n";
	print "            delayedOn\n";
	print "            delayedOff\n";
	print "            delayedReboot\n";
	print "            cancelPendingCommand\n";
	print "\n";
	exit(0);
}
	
my( $session, $error) = Net::SNMP->session(
	-hostname => $hostname, 
	-version  => "1",
	-community => $community,
);

if ( $error ) {
	die "error: $error\n";
}

if ( $session->error_status() ) {
	$error = $session->error();
	print "error: $error\n";
}

my($result);
$result = $session->get_table( -baseoid => $prod,);
if ( $session->error() ) {
	$error = $session->error();
	die "error: $error\n";
}
my($prodname) = $result->{$prod . ".0"};
unless ( $prodname ) {
	die "Unknown apc product, exiting...\n";
}

unless ( $prodname =~ /AP7921B/ ) {
	die "Unknown apc product($prodname), exiting...\n";
}

$result = $session->get_table( -baseoid => $commandoid,);

if ( $session->error() ) {
	$error = $session->error();
	die "error: $error\n";
}

#
# Get current status of all outlets
#
my(%outlets) = getoutlets($session);

if ( $info ) {
	my(%info) = getinfo($session);
	foreach ( sort keys %info ) {
		print "$_ : $info{$_}\n";
	}
	exit(0);
}
if ( $check ) {
	unless ( $commandid ) {
		print "Need command to check, exiting...\n";
		exit(1);
	}
	my($outlet);
	my($error) = 0;
	my($ok) = 0;
	my($errstr) = "Checking if status is " . $revcommand{$commandid} . ":";
	foreach $outlet ( sort keys %outlets ) {
		next unless ( $outlet );
		my($status) =  $outlets{$outlet}{status};
		if ( $status == $commandid ) {
			$ok++;
			$errstr .= " " . $outlet . "=OK";
		}
		else {
			$errstr .= " " . $outlet . "=ERR";
			$errstr =~ s/^,\s+//;
			$error++;
		}
	}

	print $errstr;

	if ( $perf ) {
		my($perfstr) = "| ok=$ok err=$error";
		print $perfstr;
	}
	print "\n";
	if ( $error ) {
		exit(1);
	}
	else {
		exit(0);
	}
}
	
elsif ( $commandid ) {
	my(@request) = ();
	my($outlet);
	my($commands) = 0;
	foreach $outlet ( sort keys %outlets ) {
		next unless ( $outlet );
		my($oid) = $outlets{$outlet}{oid};
		next unless ( $oid );
		my($status) = $outlets{$outlet}{status};
		if ( $onoutlet > 0 ) {
			next unless ( $onoutlet == $outlet );
		}

		if ( $status != $commandid ) {
			push(@request,("$oid",INTEGER,$commandid));
			print "Changing status on outlet $outlet ";
			print "from $revcommand{$status} to $revcommand{$commandid}\n";
			$commands++;
		}
		else {
			print "Current status on outlet $outlet is already $revcommand{$status}\n";
		}
	}

	if ( $commands ) {
		$result = $session->set_request(-varbindlist=>[@request]);

		if (!defined $result) {
			printf "ERROR: %s\n", $session->error();
			$session->close();
			exit 1;
		}
		my($oid);
		foreach  $oid ( sort keys %$result ) {
			print "Outlet " . lastoidindex($oid) . " now has status " . $revcommand{$result->{$oid}} . "\n";
		}
	}
	exit(0);
}
else {
	my($outlet);
	foreach $outlet ( sort keys %outlets ) {
		next unless ( $outlet );
		my($status) = $outlets{$outlet}{status};
		if ( $onoutlet > 0 ) {
			next unless ( $outlet ==  $onoutlet );
		}
		print "Outlet " . $outlet . ": " . $revcommand{$status} . "\n";
	}
}
exit(0);
