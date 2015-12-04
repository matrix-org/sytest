package SyTest::Output::Term;

use strict;
use warnings;

use constant FORMAT => "term";

# Some terminal control strings

my $RED = -t STDOUT ? "\e[31m" : "";
my $RED_B = -t STDOUT ? "\e[1;31m" : "";
my $GREEN = -t STDOUT ? "\e[32m" : "";
my $GREEN_B = -t STDOUT ? "\e[1;32m" : "";
my $YELLOW_B = -t STDOUT ? "\e[1;33m" : "";
my $CYAN = -t STDOUT ? "\e[36m" : "";
my $CYAN_B = -t STDOUT ? "\e[1;36m" : "";

my $RESET = -t STDOUT ? "\e[m" : "";

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

sub enter_multi_test
{
   shift;
   my ( $name, $expect_fail ) = @_;
   return SyTest::Output::Term::Test->new( name => $name, expect_fail => $expect_fail, multi => 1 );
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

# Overall summary
sub final_pass
{
   shift;
   my ( $expected_fail, $skipped_count ) = @_;
   print "\n${GREEN_B}All tests PASSED${RESET}";
   if( $expected_fail ) {
      print " (with $expected_fail expected failures)";
   }
   if( $skipped_count ) {
      print " (with ${YELLOW_B}$skipped_count skipped${RESET} tests)";
   }
   print "\n";
}

sub final_fail
{
   shift;
   my ( $failed ) = @_;
   print "\n${RED_B}$failed tests FAILED${RESET}\n";
}

# General diagnostic status
sub diag
{
   shift;
   my ( $message ) = @_;
   print "\n${YELLOW_B} #${RESET} $message";
}

package SyTest::Output::Term::Test {
   sub new { my $class = shift; bless { @_ }, $class }

   sub name            { shift->{name}        }
   sub expect_fail     { shift->{expect_fail} }
   sub multi           { shift->{multi}       }
   sub skipped :lvalue { shift->{skipped}     }
   sub failed :lvalue  { shift->{failed}      }
   sub failure :lvalue { shift->{failure}     }

   sub start
   {
      my $self = shift;
      print "  ${CYAN}Testing if: ${\$self->name}${RESET}... ";
      print "\n" if $self->multi;
   }

   sub progress
   {
      my $self = shift;
      my ( $message ) = @_;

      $self->{progress_printed} = 1;

      # TODO: handle multiline messages
      print "\r\e[K$message";
   }

   sub pass { }

   sub fail
   {
      my $self = shift;
      my ( $failure ) = @_;

      $self->failed++;
      $self->failure .= $failure;
   }

   sub ok
   {
      my $self = shift;
      my ( $ok, $stepname ) = @_;

      $self->progress( "" ) if $self->{progress_printed};

      $ok ?
         print "   ${CYAN}| $stepname... ${GREEN}OK${RESET}\n" :
         print "   ${CYAN}| $stepname... ${RED}NOT OK${RESET}\n";

      $self->failed++ if not $ok;
   }

   sub skip
   {
      my $self = shift;
      my ( $reason ) = @_;
      print "  ${YELLOW_B}SKIP${RESET} ${\$self->name} due to $reason\n";
      $self->skipped++;
   }

   sub leave
   {
      my $self = shift;

      return if $self->skipped;

      $self->progress( "" ) if $self->{progress_printed};

      print "   ${CYAN}+--- " if $self->multi;

      if( !$self->failed ) {
         print "${GREEN}PASS${RESET}\n";

         if( $self->expect_fail ) {
            print "${YELLOW_B}EXPECTED TO FAIL${RESET} but passed anyway\n";
         }
      }
      else {
         if( $self->expect_fail ) {
            print "${YELLOW_B}EXPECTED FAIL${RESET}:\n";
         }
         else {
            print "${RED_B}FAIL${RESET}:\n";
         }

         $self->failure = "${\$self->failed} subtests failed" if
            $self->multi and not length $self->failure;

         print " | $_\n" for split m/\n/, $self->failure;
         print " +----------------------\n";
      }
   }
}

1;
