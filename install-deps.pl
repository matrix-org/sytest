#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;

GetOptions(
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
   unless( $want_ver =~ s/^>=\s+// ) {
      print STDERR "TODO: can only perform '>=' version checks\n";
      return 1;
   }

   my $inst_ver = `$^X -M$mod -e 'print \$${mod}::VERSION'`;
   if( $inst_ver lt $want_ver ) {
      die "$mod: got $inst_ver, want $want_ver\n";
   }
   return 1;
}

sub requires
{
   my ( $mod, $ver ) = @_;

   eval { check_installed( $mod, $ver ) } and return;

   # TODO: check that some location is user-writable in @INC, and that it appears
   # somehow in PERL_{MB,MM}_OPT

   if( !$DRYRUN ) {
      # cpan returns zero even if installation fails, so we double-check
      # that the module is installed after running it.
      if ( system( $^X, "-MCPAN", "-e", qq(install "$mod") ) != 0 ) {
         print STDERR "Failed to install $mod\n";
         exit 1;
      }

      if( not eval { check_installed( $mod, $ver ) } ) {
         print STDERR "Failed to import $mod even after installing: $@\n";
         exit 1;
      }
   } else {
      print qq($^X -MCPAN -e 'install "$mod"'\n);
   }

}

do "./cpanfile";
