#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;

GetOptions(
   'n|dryrun' => \my $DRYRUN,
) or exit 1;

sub is_installed
{
   my ( $mod, $want_ver, %opts ) = @_;

   ( my $modfile = "$mod.pm" ) =~ s{::}{/}g;

   if( $opts{unload_first} ) {
      # unload the module in case we already loaded an older version
      delete $INC{$modfile};
   }

   return 0 unless( eval { require $modfile; 1 } );

   defined $want_ver or return 1;
   unless( $want_ver =~ s/^>=\s+// ) {
      print STDERR "TODO: can only perform '>=' version checks\n";
      return 1;
   }

   my $inst_ver = eval do { no strict 'refs'; ${"$mod\:\:VERSION"} };

   return $inst_ver >= $want_ver;
}

sub requires
{
   my ( $mod, $ver ) = @_;

   is_installed( $mod, $ver ) and return;

   # TODO: check that some location is user-writable in @INC, and that it appears
   # somehow in PERL_{MB,MM}_OPT

   if( !$DRYRUN ) {
      # cpan returns zero even if installation fails, so we double-check
      # that the module is installed after running it.
      system( $^X, "-MCPAN", "-e", qq(install "$mod") ) == 0 and
         is_installed( $mod, $ver, unload_first => 1 ) and
         return;

      print STDERR "Failed to install $mod\n";
      exit 1;
   }
   else {
      print qq($^X -MCPAN -e 'install "$mod"'\n);
   }

}

do "cpanfile";
