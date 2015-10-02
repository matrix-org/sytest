package SyTest::CarpByFile;

# A variant of Carp:: that hunts for the first call from a different /file/,
# regardless of package name. This is because most calls appear to come from the
# "main::" package, on account of the way we slurp+eval() the test bodies.

use strict;
use warnings;

use Exporter qw( import );
our @EXPORT_OK = qw( shortmess );
our @EXPORT    = qw( carp croak );

our $CarpLevel = 0;

sub shortmess
{
   my ( $str ) = @_;

   my $callerfile = ( caller( $CarpLevel ) )[1];
   my $level = $CarpLevel + 1;

   $level++ while ( caller( $level ) )[1] eq $callerfile;

   my ( undef, $file, $line ) = caller( $level );

   return sprintf "%s at %s line %d.\n", $str, ( caller( $level ) )[1,2];
}

sub croak
{
   local $CarpLevel = $CarpLevel + 1;
   die shortmess( $_[0] );
}

sub carp
{
   local $CarpLevel = $CarpLevel + 1;
   warn shortmess( $_[0] );
}

1;
