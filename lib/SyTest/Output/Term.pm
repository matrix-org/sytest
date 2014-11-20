package SyTest::Output::Term;

use strict;
use warnings;

use constant FORMAT => "term";

# Some terminal control strings

my $RED_B = "\e[1;31m";
my $GREEN = "\e[32m";
my $GREEN_B = "\e[1;32m";
my $YELLOW_B = "\e[1;33m";
my $CYAN = "\e[36m";
my $CYAN_B = "\e[1;36m";

my $RESET = "\e[m";

# Backspace
my $BS = "\x08";
# Erase to end of line
my $EL_TO_EOL = "\e[K";

# File status
sub run_file
{
   shift;
   my ( $filename ) = @_;
   print "${CYAN_B}Running $filename...${RESET}\n";
}

# General test status
sub enter_test
{
   shift;
   my ( $name, $expect_fail ) = @_;
   return SyTest::Output::Term::Test->new( name => $name, expect_fail => $expect_fail );
}

# General preparation status
sub start_prepare
{
   shift;
   my ( $name ) = @_;
   print "  ${CYAN}Preparing: $name${RESET}... ";
}

sub skip_prepare
{
   shift;
   my ( $name, $req ) = @_;
   print "  ${YELLOW_B}SKIP${RESET} '$name' prepararation due to lack of $req\n";
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

   print "${RED_B}FAIL${RESET}:\n";
   print " | $_\n" for split m/\n/, $failure;
   print " +----------------------\n";
}

# Wait status on longrunning tests

my $waiting = "Waiting...";

sub start_waiting
{
   shift;
   print STDERR $waiting;
}

sub stop_waiting
{
   shift;
   print STDERR $BS x length($waiting), $EL_TO_EOL;
}

# Overall summary
sub final_pass
{
   shift;
   my ( $expected_fail ) = @_;
   print STDERR "\n${GREEN_B}All tests PASSED${RESET}";
   if( $expected_fail ) {
      print STDERR " (with $expected_fail expected failures)";
   }
   print STDERR "\n";
}

sub final_fail
{
   shift;
   my ( $failed ) = @_;
   print STDERR "\n${RED_B}$failed tests FAILED${RESET}\n";
}

# General diagnostic status
sub diag
{
   shift;
   my ( $message ) = @_;
   print STDERR "$message\n";
}

package SyTest::Output::Term::Test {
   sub new { my $class = shift; bless { @_ }, $class }

   sub name        { shift->{name}        }
   sub expect_fail { shift->{expect_fail} }

   sub start
   {
      my $name = shift->name;
      print "  ${CYAN}Testing if: $name${RESET}... ";
   }

   sub pass
   {
      my $self = shift;
      print "${GREEN}PASS${RESET}\n";

      if( $self->expect_fail ) {
         print "${YELLOW_B}EXPECTED TO FAIL${RESET} but passed anyway\n";
      }
   }

   sub fail
   {
      my $self = shift;
      my ( $failure ) = @_;

      if( $self->expect_fail ) {
         print "${YELLOW_B}EXPECTED FAIL${RESET}:\n";
      }
      else {
         print "${RED_B}FAIL${RESET}:\n";
      }

      print " | $_\n" for split m/\n/, $failure;
      print " +----------------------\n";
   }

   sub skip
   {
      my $name = shift->name;
      my ( $req ) = @_;
      print "  ${YELLOW_B}SKIP${RESET} $name due to lack of $req\n";
   }
}

1;
