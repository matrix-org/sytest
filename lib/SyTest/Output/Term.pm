package SyTest::Output::Term;

use strict;
use warnings;

use constant FORMAT => "term";

# File status
sub run_file
{
   shift;
   my ( $filename ) = @_;
   print "\e[1;36mRunning $filename...\e[m\n";
}

# General test status
sub start_test
{
   shift;
   my ( $name ) = @_;
   print "  \e[36mTesting if: $name\e[m... ";
}

sub pass_test
{
   shift;
   my ( $expect_fail ) = @_;
   print "\e[32mPASS\e[m\n";

   if( $expect_fail ) {
      print "\e[1;33mEXPECTED TO FAIL\e[m but passed anyway\n";
   }
}

sub fail_test
{
   shift;
   my ( $failure, $expect_fail ) = @_;

   if( $expect_fail ) {
      print "\e[1;33mEXPECTED FAIL\e[m:\n";
   }
   else {
      print "\e[1;31mFAIL\e[m:\n";
   }

   print " | $_\n" for split m/\n/, $failure;
   print " +----------------------\n";
}

sub skip_test
{
   shift;
   my ( $name, $req ) = @_;
   print "  \e[1;33mSKIP\e[m $name due to lack of $req\n";
}

# General preparation status
sub start_prepare
{
   shift;
   my ( $name ) = @_;
   print "  \e[36mPreparing: $name\e[m... ";
}

sub skip_prepare
{
   shift;
   my ( $name, $req ) = @_;
   print "  \e[1;33mSKIP\e[m '$name' prepararation due to lack of $req\n";
}

sub pass_prepare
{
   shift;
   print "DONE\n";
}

sub fail_prepare
{
   shift;
   my ( $failure ) = @_;

   print "\e[1;31mFAIL\e[m:\n";
   print " | $_\n" for split m/\n/, $failure;
   print " +----------------------\n";
}

# Wait status on longrunning tests

sub start_waiting
{
   shift;
   print STDERR "  Waiting...";
}

sub stop_waiting
{
   shift;
   print STDERR "\r\e[2K";
}

# Overall summary
sub final_pass
{
   shift;
   my ( $expected_fail ) = @_;
   print STDERR "\n\e[1;32mAll tests PASSED\e[m";
   if( $expected_fail ) {
      print STDERR " (with $expected_fail expected failures)";
   }
   print STDERR "\n";
}

sub final_fail
{
   shift;
   my ( $failed ) = @_;
   print STDERR "\n\e[1;31m$failed tests FAILED\e[m\n";
}

# General diagnostic status
sub diag
{
   shift;
   my ( $message ) = @_;
   print STDERR "$message\n";
}

1;
