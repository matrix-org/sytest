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

my $BLUE_BG = -t STDOUT ? "\e[44m" : "";

my $RESET_FG = -t STDOUT ? "\e[39m" : "";
my $RESET = -t STDOUT ? "\e[m" : "";

my $CLEARLINE = "\r\e[K";
my $PREVLINE = "\eM";

# Some private functions, since there's just one terminal
{
   my $partial;
   my $status;

   sub _printline
   {
      my ( $message ) = @_;

      print join "",
         ( length $partial || length $status ? $CLEARLINE : () ),
         ( length $partial && length $status ? $PREVLINE . $CLEARLINE : () ),
         $message, "\n",
         ( length $partial ? $partial : () ),
         ( length $partial && length $status ? "\n" : () ),
         ( length $status ? $status : () );
   }

   sub _morepartial
   {
      my ( $message ) = @_;
      my $was_partial = length $partial;

      $partial .= $message;

      print join "",
         ( length $status && $was_partial ? $PREVLINE : () ),
         $CLEARLINE, $partial,
         ( length $status ? ( "\n", $status ) : () );
   }

   sub _finishpartial
   {
      my ( $message ) = @_;
      my $was_partial = length $partial;

      print join "",
         ( length $status && $was_partial ? $CLEARLINE . $PREVLINE : () ),
         $CLEARLINE, $partial, $message,
         ( length $status ? ( "\n", $status ) : ( "\n" ) );

      undef $partial;
   }

   sub _printstatus
   {
      print "\n" if !length $status and length $partial;
      ( $status ) = @_;
      print $CLEARLINE . $status;
   }

   sub _clearstatus
   {
      print $CLEARLINE if length $status;
      undef $status;
   }
}

# File status
sub run_file
{
   shift;
   my ( $filename ) = @_;
   _printline "${CYAN_B}Running $filename...${RESET}";
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
   _printline "${YELLOW_B} #${RESET} $message";
}

sub diagwarn
{
   shift;
   my ( $message ) = @_;
   _printline "${RED_B} **${RESET} $message";
}

sub status
{
   shift;
   my %args = @_;

   return _clearstatus unless %args;

   my $message = join " | ",
      sprintf( "Tests: %d / %d", $args{done}, $args{tests} ),
      ( $args{failed} ? sprintf( "${RED_B}%d FAIL${RESET_FG}", $args{failed} )
                      : "OK" ),
      ( $args{skipped} ? sprintf( "${YELLOW_B}%d SKIPPED${RESET_FG}", $args{skipped} )
                       : () );

   _printstatus "${BLUE_BG}$message${RESET}";
}

package SyTest::Output::Term::Test {

   BEGIN {
      *_printline     = \&SyTest::Output::Term::_printline;
      *_morepartial   = \&SyTest::Output::Term::_morepartial;
      *_finishpartial = \&SyTest::Output::Term::_finishpartial;
   }

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

      my $message = "  ${CYAN}Testing if: ${\$self->name}${RESET}... ";
      $self->multi ?
         _printline $message :
         _morepartial $message;
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

      $ok ?
         _printline "   ${CYAN}| $stepname... ${GREEN}OK${RESET}" :
         _printline "   ${CYAN}| $stepname... ${RED}NOT OK${RESET}";

      $self->failed++ if not $ok;
   }

   sub skip
   {
      my $self = shift;
      my ( $reason ) = @_;

      _printline "  ${YELLOW_B}SKIP${RESET} ${\$self->name} due to $reason\n";

      $self->skipped++;
   }

   sub leave
   {
      my $self = shift;

      return if $self->skipped;

      _morepartial "   ${CYAN}+--- " if $self->multi;

      if( !$self->failed ) {
         _finishpartial "${GREEN}PASS${RESET}";

         if( $self->expect_fail ) {
            _printline "${YELLOW_B}EXPECTED TO FAIL${RESET} but passed anyway\n";
         }
      }
      else {
         if( $self->expect_fail ) {
            _finishpartial "${YELLOW_B}EXPECTED FAIL${RESET}:";
         }
         else {
            _finishpartial "${RED_B}FAIL${RESET}:";
         }

         $self->failure = "${\$self->failed} subtests failed" if
            $self->multi and not length $self->failure;

         _printline " | $_" for split m/\n/, $self->failure;
         _printline " +----------------------";
      }
   }
}

1;
