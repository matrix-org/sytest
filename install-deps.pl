#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;

use CPAN;

GetOptions(
   'T|notest' => \my $NOTEST,
   'n|dryrun' => \my $DRYRUN,
) or exit 1;

sub check_installed
{
   my ( $mod, $want_ver, %opts ) = @_;

   # we do the import via a subprocess. The main reason for this is that, as
   # things get installed, the number of directories to be scanned increases
   # (for example, we may add architecture-dependent directories), and perl
   # only checks for these to add to @INC at startup.
   #
   # There are other benefits in doing so:
   #  - we don't pollute the installation process with lots of random modules
   #  - we ensure that each module really is installable in its own right.

   my $res = `$^X -M$mod -e 1 2>&1`;
   if( $? != 0 ) {
      die "unable to import $mod: $res";
   }

   defined $want_ver or return 1;
   my $inst_ver = `$^X -M$mod -e 'print \$${mod}::VERSION'`;

   if( $want_ver =~ s/^>=\s*// ) {
      if( $inst_ver lt $want_ver ) {
         die "$mod: got $inst_ver, want >=$want_ver\n";
      }
   } elsif( $want_ver =~ s/^<\s*// ) {
      if( $inst_ver ge $want_ver ) {
         die "$mod: got $inst_ver, want <$want_ver\n";
      }
   } else {
      print STDERR "TODO: can only perform '<' and '>=' version checks: cannot support $want_ver\n";
      return 1;
   }

   return 1;
}

sub requires
{
   my ( $mod, $ver, $dist_path ) = @_;

   eval { check_installed( $mod, $ver ) } and return;

   $dist_path //= $mod;

   # TODO: check that some location is user-writable in @INC, and that it appears
   # somehow in PERL_{MB,MM}_OPT

   if( !$DRYRUN ) {
      print STDERR "\n\n**** install-deps.pl: Installing $mod ****\n";

      if( $NOTEST ) {
         CPAN::Shell->notest('install', $dist_path);
      } else {
         CPAN::Shell->install($dist_path);
      }

      if( not eval { check_installed( $mod, $ver ) } ) {
         print STDERR "Failed to import $mod even after installing: $@\n";
         exit 1;
      }
   } else {
      print qq($^X -MCPAN -e 'install "$dist_path"'\n);
   }
}

# $CPAN::DEBUG=2047;

# load the config before we override things
CPAN::HandleConfig->load;

# tell CPAN to halt on first failure, to avoid hiding the error with errors
# from things that are now certain to fail
$CPAN::Config->{halt_on_failure} = 1;


# Alien::Sodium will think it is building for javascript if the EMSCRIPTEN env
# var is set.
delete $ENV{EMSCRIPTEN};

do "./cpanfile";
