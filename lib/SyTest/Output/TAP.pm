package SyTest::Output::TAP;

use strict;
use warnings;

use constant FORMAT => "tap";

STDOUT->autoflush(1);

# File status
sub run_file {}

my $next_test_num = 1;

# General test status
sub enter_test
{
   shift;
   my ( $name ) = @_;
   return SyTest::Output::TAP::Test->new( $name, $next_test_num++ );
}

# General preparation status
my $running;
sub start_prepare
{
   shift;
   ( $running ) = @_;
}

sub skip_prepare
{
   shift;
   my ( $name, $req ) = @_;
   print "ok $next_test_num $name # skip Missing requirement $req\n";
   $next_test_num++;
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
sub start_waiting
{
}

sub stop_waiting
{
}

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

# General diagnostic status
sub diag
{
   shift;
   my ( $message ) = @_;
   print "# $message\n";
}

package SyTest::Output::TAP::Test {
   sub new { my ( $class, $name, $num ) = @_; bless [ $name, $num ], $class }
   sub name { shift->[0] }
   sub num  { shift->[1] }

   sub start {}

   sub pass
   {
      my $self = shift;
      my ( $expect_fail ) = @_;
      print "ok ${\$self->num} ${\$self->name}\n";
   }

   sub fail
   {
      my $self = shift;
      my ( $failure, $expect_fail ) = @_;
      print "not ok ${\$self->num} ${\$self->name}" . ( $expect_fail ? " # TODO expected fail" : "" ) . "\n";

      print "# $_\n" for split m/\n/, $failure;
   }

   sub skip
   {
      my $self = shift;
      my ( $req ) = @_;
      print "ok ${\$self->num} ${\$self->name} # skip Missing requirement $req\n";
   }
}

1;
