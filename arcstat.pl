#!/bin/perl -w
#
# Print out ZFS ARC Statistics exported via kstat(1)
# For a definition of fields, or usage, use arctstat.pl -v
#
# Author: Neelakanth Nadgir http://blogs.sun.com/realneel
# Comments/Questions/Feedback to neel_sun.com or neel_gnu.org
#
# CDDL HEADER START
# 
# The contents of this file are subject to the terms of the
# Common Development and Distribution License, Version 1.0 only
# (the "License").  You may not use this file except in compliance
# with the License.
# 
# You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
# or http://www.opensolaris.org/os/licensing.
# See the License for the specific language governing permissions
# and limitations under the License.
# 
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at usr/src/OPENSOLARIS.LICENSE.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
# 
# CDDL HEADER END
#
#
# Fields have a fixed width. Every interval, we fill the "v"
# hash with its corresponding value (v[field]=value) using calculate(). 
# @hdr is the array of fields that needs to be printed, so we
# just iterate over this array and print the values using our pretty printer.

use strict;
use POSIX qw(strftime);
use Sun::Solaris::Kstat;
use Getopt::Long;
use IO::Handle;

my %cols = (# HDR => [Size, Scale, Description]
	"time"		=>[8, "N/A", "Time"],
	"hits"		=>[4, 1000, "Arc reads per second"],
	"miss"		=>[4, 1000, "Arc misses per second"],
	"read"		=>[4, 1000, "Total Arc accesses per second"],
	"hit%"		=>[4, 100, "Arc Hit percentage"],
	"miss%"		=>[5, 100, "Arc miss percentage"],
	"dhit"		=>[4, 1000, "Demand Data hits per second"],
	"dmis"		=>[4, 1000, "Demand Data misses per second"],
	"dh%"		=>[3, 100, "Demand Data hit percentage"],
	"dm%"		=>[3, 100, "Demand Data miss percentage"],
	"phit"		=>[4, 1000, "Prefetch hits per second"],
	"pmis"		=>[4, 1000, "Prefetch misses per second"],
	"ph%"		=>[3, 100, "Prefetch hits percentage"],
	"pm%"		=>[3, 100, "Prefetch miss percentage"],
	"mhit"		=>[4, 1000, "Metadata hits per second"],
	"mmis"		=>[4, 1000, "Metadata misses per second"],
	"mread"		=>[4, 1000, "Metadata accesses per second"],
	"mh%"		=>[3, 100, "Metadata hit percentage"],
	"mm%"		=>[3, 100, "Metadata miss percentage"],
	"arcsz"		=>[5, 1024, "Arc Size"],
	"c" 		=>[4, 1024, "Arc Target Size"],
	"mfu" 		=>[4, 1000, "MFU List hits per second"],
	"mru" 		=>[4, 1000, "MRU List hits per second"],
	"mfug" 		=>[4, 1000, "MFU Ghost List hits per second"],
	"mrug" 		=>[4, 1000, "MRU Ghost List hits per second"],
	"eskip"		=>[5, 1000, "evict_skip per second"],
	"mtxmis"	=>[6, 1000, "mutex_miss per second"],
	"rmis"		=>[4, 1000, "recycle_miss per second"],
	"dread"		=>[5, 1000, "Demand data accesses per second"],
	"pread"		=>[5, 1000, "Prefetch accesses per second"],
	"l2hits"	=>[6, 1000, "L2ARC hits per second"],
	"l2miss"	=>[6, 1000, "L2ARC misses per second"],
	"l2read"	=>[6, 1000, "Total L2ARC accesses per second"],
	"l2hit%"	=>[6, 100, "L2ARC access hit percentage"],
	"l2miss%"	=>[7, 100, "L2ARC access miss percentage"],
	"l2size"	=>[6, 1024, "Size of the L2ARC"],
	"l2bytes"	=>[7, 1024, "bytes read per second from the L2ARC"],
);
my %v=();
my @hdr = qw(time read miss miss% dmis dm% pmis pm% mmis mm% arcsz c);
my @xhdr = qw(time mfu mru mfug mrug eskip mtxmis rmis dread pread read);
my $int = 1;		# Print stats every 1 second by default
my $count = 0;		# Print stats forever
my $hdr_intr = 20;	# Print header every 20 lines of output
my $opfile = "";
my $sep = "  ";		# Default seperator is 2 spaces
my $version = "0.3";
my $cmd = "Usage: arcstat.pl [-hvx] [-f fields] [-o file] [interval [count]]\n";
my %cur;
my %d;
my $out;
my $kstat = Sun::Solaris::Kstat->new();
STDOUT->autoflush;

sub detailed_usage {
	print STDERR "Arcstat version $version\n$cmd";
	print STDERR "Field definitions are as follows\n";
	foreach my $hdr (keys %cols) {
		print STDERR sprintf("%7s : %s\n", $hdr, $cols{$hdr}[2]);
	}
#	print STDERR "\nNote: K=10^3 M=10^6 G=10^9 and so on\n";
	exit(1);

}

sub usage {
	print STDERR "Arcstat version $version\n$cmd";
	print STDERR "\t -x : Print extended stats\n";
	print STDERR "\t -f : Specify specific fields to print (see -v)\n";
	print STDERR "\t -o : Print stats to file\n";
	print STDERR "\t -s : Specify a seperator\n\nExamples:\n";
	print STDERR "\tarcstat -o /tmp/a.log 2 10\n";
	print STDERR "\tarcstat -s , -o /tmp/a.log 2 10\n";
	print STDERR "\tarcstat -v\n";
	print STDERR "\tarcstat -f time,hit%,dh%,ph%,mh%\n";
	exit(1);
}

sub init {
	my $desired_cols;
	my $xflag = '';
	my $hflag = '';
	my $vflag;
	my $res = GetOptions('x' => \$xflag,
		'o=s' => \$opfile,
		'help|h|?' => \$hflag,
		'v' => \$vflag,
		's=s' => \$sep,
		'f=s' => \$desired_cols);
	$int = $ARGV[0] || $int;
	$count = $ARGV[1] || $count;
	usage() if !$res or $hflag or ($xflag and $desired_cols);
	detailed_usage() if $vflag;
	@hdr = @xhdr if $xflag;		#reset headers to xhdr
	if ($desired_cols) {
		@hdr = split(/[ ,]+/, $desired_cols);
		# Now check if they are valid fields
		my @invalid = ();
		foreach my $ele (@hdr) {
			push(@invalid, $ele) if not exists($cols{$ele});
		}
		if (scalar @invalid > 0) {
			print STDERR "Invalid column definition! -- "
				. "@invalid\n\n";
			usage();
		}
	}
	if ($opfile) {
		open($out, ">$opfile") ||die "Cannot open $opfile for writing";
		$out->autoflush;
		select $out;
	}
}

# Capture kstat statistics. We maintain 3 hashes, prev, cur, and
# d (delta). As their names imply they maintain the previous, current,
# and delta (cur - prev) statistics.
sub snap_stats {
	my %prev = %cur;
	if ($kstat->update()) {
		printf("<State Changed>\n");
	}
	my $hashref_cur = $kstat->{"zfs"}{0}{"arcstats"};
	%cur = %$hashref_cur;
	foreach my $key (keys %cur) {
		next if $key =~ /class/;
		if (defined $prev{$key}) {
			$d{$key} = $cur{$key} - $prev{$key};
		} else {
			$d{$key} = $cur{$key};
		}
	}
}

# Pretty print num. Arguments are width, scale, and num
sub prettynum {
	my @suffix=(' ','K', 'M', 'G', 'T');
	my $num = $_[2] || 0;
	my $scale = $_[1];
	my $sz = $_[0];
	my $index = 0;
	my $save = 0;

	return sprintf("%s", $num) if not $num =~ /^[0-9\.]+$/;

	while ($num > $scale and $index < 5) {
		$save = $num;
		$num = $num/$scale;
		$index++;
	}

	return sprintf("%*d", $sz, $num) if ($index == 0);
	if (($save / $scale) < 10) {
		return sprintf("%*.1f%s", $sz - 1, $num,$suffix[$index]);
	} else {
		return sprintf("%*d%s", $sz - 1, $num,$suffix[$index]);
	}
}

sub print_values {
	foreach my $col (@hdr) {
		printf("%s%s", prettynum($cols{$col}[0], $cols{$col}[1],
			$v{$col}), $sep);
	}
	printf("\n");
}

sub print_header {
	foreach my $col (@hdr) {
		printf("%*s%s", $cols{$col}[0], $col, $sep);
	}
	printf("\n");
}

sub calculate {
	%v=();
	$v{"time"} = strftime("%H:%M:%S", localtime);
	$v{"hits"} = $d{"hits"}/$int;
	$v{"miss"} = $d{"misses"}/$int;
	$v{"read"} = $v{"hits"} + $v{"miss"};
	$v{"hit%"} = 100*$v{"hits"}/$v{"read"} if $v{"read"} > 0;
	$v{"miss%"} = 100 - $v{"hit%"} if $v{"read"} > 0;

	$v{"dhit"} = ($d{"demand_data_hits"} + 
		$d{"demand_metadata_hits"})/$int;
	$v{"dmis"} = ($d{"demand_data_misses"} + 
		$d{"demand_metadata_misses"})/$int;

	$v{"dread"} = $v{"dhit"} + $v{"dmis"};
	$v{"dh%"} = 100 * $v{"dhit"}/$v{"dread"} if $v{"dread"} > 0;
	$v{"dm%"} = 100 - $v{"dh%"} if $v{"dread"} > 0;

	$v{"phit"}=($d{"prefetch_data_hits"} + 
		$d{"prefetch_metadata_hits"})/$int;
	$v{"pmis"}=($d{"prefetch_data_misses"}
		+$d{"prefetch_metadata_misses"})/$int;

	$v{"pread"} = $v{"phit"} + $v{"pmis"};
	$v{"ph%"} = 100 * $v{"phit"}/$v{"pread"} if $v{"pread"} > 0;
	$v{"pm%"} = 100 - $v{"ph%"} if $v{"pread"} > 0;

	$v{"mhit"}=($d{"prefetch_metadata_hits"} + 
		$d{"demand_metadata_hits"})/$int;
	$v{"mmis"}=($d{"prefetch_metadata_misses"}
		+$d{"demand_metadata_misses"})/$int;

	$v{"mread"} = $v{"mhit"} + $v{"mmis"};
	$v{"mh%"} = 100 * $v{"mhit"}/$v{"mread"} if $v{"mread"} > 0;
	$v{"mm%"} = 100 - $v{"mh%"} if $v{"mread"} > 0;

	$v{"arcsz"} = $cur{"size"};
	$v{"c"} = $cur{"c"};
	$v{"mfu"} = $d{"hits"}/$int;
	$v{"mru"} = $d{"mru_hits"}/$int;
	$v{"mrug"} = $d{"mru_ghost_hits"}/$int;
	$v{"mfug"} = $d{"mru_ghost_hits"}/$int;
	$v{"eskip"} = $d{"evict_skip"}/$int;
	$v{"rmiss"} = $d{"recycle_miss"}/$int;
	$v{"mtxmis"} = $d{"mutex_miss"}/$int;

	$v{"l2hits"} = $d{"l2_hits"}/$int;
	$v{"l2miss"} = $d{"l2_misses"}/$int;
	$v{"l2read"} = $v{"l2hits"} + $v{"l2miss"};
	$v{"l2hit%"} = 100 * $v{"l2hits"}/$v{"l2read"} if $v{"l2read"} > 0;
	$v{"l2miss%"} = 100 - $v{"l2hit%"} if $v{"l2read"} > 0;
	$v{"l2size"} = $cur{"l2_size"};
	$v{"l2bytes"} = $d{"l2_read_bytes"}/$int;
}

sub main {
	my $i = 0;
	my $count_flag = 0;

	init();
	if ($count > 0) { $count_flag = 1; }
	while (1) {
		print_header() if ($i == 0);
		snap_stats();
		calculate();
		print_values();
		last if ($count_flag == 1 && $count-- <= 1);
		$i = ($i == $hdr_intr) ? 0 : $i+1;
		sleep($int);
	}
	close($out) if defined $out;
}

&main;
