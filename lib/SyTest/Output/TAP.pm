package SyTest::Output::TAP;

use strict;
use warnings;

use constant FORMAT => "tap";

STDOUT->autoflush(1);

# File status
sub run_file {}

my $next_test_num = 1;

# General test status
my $running;
sub start_test
{
   shift;
   ( $running ) = @_;
}

sub pass_test
{
   shift;
   my ( $expect_fail ) = @_;
   print "ok $next_test_num $running\n";
   $next_test_num++;
}

sub fail_test
{
   shift;
   my ( $failure, $expect_fail ) = @_;
   print "not ok $next_test_num $running" . ( $expect_fail ? " # TODO" : "" ) . "\n";
   $next_test_num++;

   print "# $_\n" for split m/\n/, $failure;
}

sub skip_test
{
   shift;
   my ( $name, $req ) = @_;
   print "ok $next_test_num $name # skip Missing requirement $req\n";
   $next_test_num++;
}

# General preparation status
sub start_prepare
{
   shift;
   ( $running ) = @_;
}

sub pass_prepare
{
   print "ok $next_test_num prepared $running\n";
   $next_test_num;
}

sub fail_prepare
{
   shift;
   my ( $failure ) = @_;
   print "not ok $next_test_num prepared $running\n";
   $next_test_num++;

   print "# $_\n" for split m/\n/, $failure;
}

# Wait status on longrunning tests
sub start_waiting {}
sub stop_waiting  {}

# Overall summary
sub final_pass
{
   shift;
   print "1..$next_test_num\n";
}

sub final_fail
{
   shift;
   print "1..$next_test_num\n";
}

sub diag
{
   shift;
   my ( $message ) = @_;
   print "# $message\n";
}

1;
