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

   ( my $modfile = "$mod.pm" ) =~ s{::}{/}g;

   if( $opts{unload_first} ) {
      # unload the module in case we already loaded an older version
      delete $INC{$modfile};
   }

   require $modfile;

   defined $want_ver or return 1;
   unless( $want_ver =~ s/^>=\s+// ) {
      print STDERR "TODO: can only perform '>=' version checks\n";
      return 1;
   }

   my $inst_ver = do { no strict 'refs'; ${"$mod\:\:VERSION"} };

   if( $inst_ver < $want_ver ) {
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

      if( not eval { check_installed( $mod, $ver, unload_first => 1 ) } ) {
         print STDERR "Failed to import $mod even after installing: $@\n";
         exit 1;
      }
   } else {
      print qq($^X -MCPAN -e 'install "$mod"'\n);
   }

}

do "./cpanfile";
