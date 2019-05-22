package SyTest::Output::TAP;

use strict;
use warnings;

use constant FORMAT => "tap";

STDOUT->autoflush(1);
STDERR->autoflush(1);

# File status
sub run_file {
   shift;
   my ( $filename ) = @_;

   print STDERR "$filename:\n";
}

my $test_num;

# General test status
sub enter_test
{
   shift;
   my ( $name, $expect_fail ) = @_;
   return SyTest::Output::TAP::Test->new(
      name => $name,
      num  => ++$test_num,
      expect_fail => $expect_fail,
   );
}

sub enter_multi_test
{
   shift;
   my ( $name, $expect_fail ) = @_;
   return SyTest::Output::TAP::Test->new(
      name => $name,
      num  => ++$test_num,
      expect_fail => $expect_fail,
      multi => 1,
   );
}

# Overall summary
sub final_pass
{
   shift;
   print "1..$test_num\n";
}

sub final_fail
{
   shift;
   print "1..$test_num\n";
}

# General diagnostic status
sub diag
{
   shift;
   my ( $message ) = @_;
   print "# $message\n";
}

sub diagwarn
{
   shift;
   my ( $message ) = @_;
   print "#** $message\n";
}

sub status {}

package SyTest::Output::TAP::Test {
   sub new { my $class = shift; bless { subnum => 0, @_ }, $class }

   sub name            { shift->{name}        }
   sub num             { shift->{num}         }
   sub expect_fail     { shift->{expect_fail} }
   sub multi           { shift->{multi}       }
   sub passed  :lvalue { shift->{passed}      }
   sub skipped :lvalue { shift->{skipped}     }
   sub failed  :lvalue { shift->{failed}      }
   sub failure :lvalue { shift->{failure}     }
   sub subnum  :lvalue { shift->{subnum}      }

   sub start {
      my $self = shift;

      print STDERR "    Test ${\$self->num} ${\$self->name}...\n";
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

      my $subnum = ++$self->subnum;

      print "  ", ( $ok ? "ok" : "not ok" ), " $subnum $stepname (${\$self->name})\n";
   }

   sub skip
   {
      my $self = shift;
      my ( $reason ) = @_;
      print "ok ${\$self->num} ${\$self->name} # skip $reason\n";
      $self->skipped++;
   }

   sub leave
   {
      my $self = shift;

      return if $self->skipped;

      if( $self->multi ) {
         print "  1..${\$self->subnum}\n";
         $self->failure = "${\$self->failed} subtests failed" if $self->failed and not length $self->failure;
      }

      my $name = $self->name;

      if( !$self->failed ) {
         $name .= " (${\$self->subnum} subtests)" if $self->multi;

         print "ok ${\$self->num} " .
            ( $self->expect_fail ? "(expected fail) " : "" ) .
            $name .
            ( $self->expect_fail ? " # TODO passed but expected fail" : "" ) . "\n";
      } else {
         # for expected fails, theoretically all we need to do is write the
         # TODO, but Jenkins' 'TAP Test results' page is arse and doesn't distinguish
         # between expected and unexpected fails, so stick it in the name too.
         print "not ok ${\$self->num} " .
            ( $self->expect_fail ? "(expected fail) " : "" ) .
            $name .
            ( $self->expect_fail ? " # TODO expected fail" : "" ) . "\n";

         print "# $_\n" for split m/\n/, $self->failure;
      }
   }
}

1;
