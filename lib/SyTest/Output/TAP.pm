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
   my ( $name, $expect_fail ) = @_;
   return SyTest::Output::TAP::Test->new(
      name => $name,
      num  => $next_test_num++,
      expect_fail => $expect_fail,
   );
}

sub enter_multi_test
{
   shift;
   my ( $name, $expect_fail ) = @_;
   return SyTest::Output::TAP::Test->new(
      name => $name,
      expect_fail => $expect_fail,
      multi => 1,
   );
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
   sub new { my $class = shift; bless { @_ }, $class }

   sub name            { shift->{name}        }
   sub num             { shift->{num}         }
   sub expect_fail     { shift->{expect_fail} }
   sub multi           { shift->{multi}       }
   sub skipped :lvalue { shift->{skipped}     }
   sub failed :lvalue  { shift->{failed}      }
   sub failure :lvalue { shift->{failure}     }
   sub subnum :lvalue  { shift->{subnum}      }

   sub start {}

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

      my $subnum = ++$self->subnum;

      print "  ", ( $ok ? "ok" : "not ok" ), " $subnum $stepname (${\$self->name})\n";
   }

   sub skip
   {
      my $self = shift;
      my ( $req ) = @_;
      print "ok ${\$self->num} ${\$self->name} # skip Missing requirement $req\n";
      $self->skipped++;
   }

   sub leave
   {
      my $self = shift;

      return if $self->skipped;

      if( $self->multi ) {
         print "  1..${\$self->subnum}\n";
         return;
      }

      if( !$self->failed ) {
         print "ok ${\$self->num} ${\$self->name}\n";
      }
      else {
         print "not ok ${\$self->num} ${\$self->name}" . ( $self->expect_fail ? " # TODO expected fail" : "" ) . "\n";

         print "# $_\n" for split m/\n/, $self->failure;
      }
   }
}

1;
