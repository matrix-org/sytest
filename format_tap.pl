#!/usr/bin/perl -l
use strict;
use warnings FATAL => 'all';

use TAP::Parser;

# Get tap results filename and CI build name from argv
my $tap_file = $ARGV[0];
my $build_name = $ARGV[1];

my $parser = TAP::Parser->new( { source => $tap_file } );
my $in_error = 0;
my @out = ( "### TAP Output for $build_name" );

while ( my $result = $parser->next ) {
   if ( $result->is_test ) {
      # End an existing error block
      if ( $in_error == 1 ) {
         push( @out, "" );
         push( @out, "</pre></code></details>" );
         push( @out, "" );
         push( @out, "----" );
         push( @out, "" );
      }

      $in_error = 0;

      # Start a new error block
      if ( not $result->is_ok ) {
         $in_error = 1;

         my $number = $result->number;
         my $description = $result->description;

         push(@out, "FAILURE Test #$number: ``$description``");
         push(@out, "");
         push(@out, "<details><summary>Show log</summary><code><pre>");
      }
   } elsif ( $result->is_comment and $in_error == 1 ) {
      # Print error contents
      push( @out, $result->raw );
   }
}

# Print out the contents of @out, leaving off the last little formatting bits
foreach my $line ( @out[0..$#out-3] ) {
   # The -l in the hashbang makes print append a newline to the content
   print $line;
}
