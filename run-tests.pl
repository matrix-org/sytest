#!/usr/bin/env perl

use strict;
use warnings;
use 5.014; # package NAME { BLOCK }

use lib 'lib';

use Carp;

use Future;
use IO::Async::Loop;

use Data::Dump qw( pp );
use File::Basename qw( basename );
use Getopt::Long qw( :config no_ignore_case );
use IO::Socket::SSL;
use List::Util 1.33 qw( first all );

use SyTest::Synapse;
use SyTest::HTTPClient;

use Module::Pluggable
   sub_name    => "output_formats",
   search_path => [ "SyTest::Output" ],
   require     => 1;

GetOptions(
   'N|number=i'    => \(my $NUMBER = 2),
   'C|client-log+' => \my $CLIENT_LOG,
   'S|server-log+' => \my $SERVER_LOG,
   'd|synapse-directory=s' => \(my $SYNAPSE_DIR = "../synapse"),

   's|stop-on-fail+' => \my $STOP_ON_FAIL,

   'O|output-format=s' => \(my $OUTPUT_FORMAT = "term"),
) or exit 1;

my $output = first { $_->can( "FORMAT") and $_->FORMAT eq $OUTPUT_FORMAT } output_formats()
   or die "Unrecognised output format $OUTPUT_FORMAT\n";

if( $CLIENT_LOG ) {
   require Net::Async::HTTP;
   require Class::Method::Modifiers;
   require JSON;

   Class::Method::Modifiers::install_modifier( "Net::Async::HTTP",
      around => _do_request => sub {
         my ( $orig, $self, %args ) = @_;
         my $request = $args{request};

         my $request_uri = $request->uri;
         if( $request_uri->path =~ m{/events$} ) {
            print STDERR "\e[1;32mPolling events\e[m\n";

            return $orig->( $self, %args )
               ->on_done( sub {
                  my ( $response ) = @_;

                  eval {
                     my $content_decoded = JSON::decode_json( $response->content );
                     my $events = $content_decoded->{chunk};
                     foreach my $event ( @$events ) {
                        print STDERR "\e[1;33mReceived event\e[m:\n";
                        print STDERR "  $_\n" for split m/\n/, pp( $event );
                        print STDERR "-- \n";
                     }
                     print "\e[1;33mNo events\e[m\n" unless @$events;

                     1;
                  } or do {
                     print STDERR "Could not deparse JSON event return - $@";
                  };
               }
            );
         }
         else {
            print STDERR "\e[1;32mRequesting\e[m:\n";
            print STDERR "  $_\n" for split m/\n/, $request->as_string;
            print STDERR "-- \n";

            return $orig->( $self, %args )
               ->on_done( sub {
                  my ( $response ) = @_;

                  print STDERR "\e[1;33mResponse\e[m from $request_uri:\n";
                  print STDERR "  $_\n" for split m/\n/, $response->as_string;
                  print STDERR "-- \n";
               }
            );
         }
      }
   );
}

my $loop = IO::Async::Loop->new;

# Start up 3 homeservers

my %synapses_by_port;
END {
   $output->diag( "Killing synapse servers " . join " ", map { "[${\$_->pid}]" } values %synapses_by_port )
      if %synapses_by_port;

   kill INT => $_->pid for values %synapses_by_port;
}
$SIG{INT} = sub { exit 1 };

my @PORTS = 8001 .. 8000+$NUMBER;
my @f;
foreach my $port ( @PORTS ) {
   my $synapse = $synapses_by_port{$port} = SyTest::Synapse->new(
      synapse_dir  => $SYNAPSE_DIR,
      port         => $port,
      output       => $output,
      print_output => $SERVER_LOG,
   );
   $loop->add( $synapse );

   push @f, Future->wait_any(
      $synapse->started_future,

      $loop->delay_future( after => 20 )
         ->then_fail( "Synapse server on port $port failed to start" ),
   );
}

Future->needs_all( @f )->get;

# Some tests create objects as a side-effect that later tests will depend on,
# such as clients, users, rooms, etc... These are called the Environment
my %test_environment;

$test_environment{http_clients} = [ map {
   my $port = $_;
   my $client = SyTest::HTTPClient->new(
      uri_base => "https://localhost:$port/_matrix/client/api/v1",
   );
   $loop->add( $client );
   $client;
} @PORTS ];
$test_environment{first_http_client} = $test_environment{http_clients}->[0];

sub provide
{
   my ( $name, $value ) = @_;
   exists $test_environment{$name} and
      carp "Overwriting existing test environment key '$name'";

   $test_environment{$name} = $value;
}

sub unprovide
{
   my @names = @_;

   delete $test_environment{$_} for @names;
}

my $failed;
my $expected_fail;

sub _run_test
{
   my ( $t, %params ) = @_;

   my @reqs;
   foreach my $req ( @{ $params{requires} || [] } ) {
      push @reqs, $test_environment{$req} and next if $test_environment{$req};

      $t->skip( $req );
      return;
   }

   $t->start;

   return eval {
      my $check = $params{check};
      if( my $do = $params{do} ) {
         if( $check ) {
            eval { Future->wrap( $check->( @reqs ) )->get } and
               warn "Warning: ${\$t->name} was already passing before we did anything\n";
         }

         Future->wrap( $do->( @reqs ) )->get;
      }

      if( $check ) {
         Future->wrap( $check->( @reqs ) )->get or
            die "Test check function failed to return a true value"
      }

      if( my $await = $params{await} ) {
         Future->wait_any(
            Future->wrap( $await->( @reqs ) )->then( sub {
               my ( $success ) = @_;
               $success or die "'await' check did not return a true value";
               Future->done
            }),

            $loop->delay_future( after => 2 )
               ->then( sub {
                  $output->start_waiting;
                  $loop->new_future->on_cancel( sub { $output->stop_waiting });
               }),

            $loop->delay_future( after => $params{timeout} // 10 )
               ->then_fail( "Timed out waiting for 'await'" )
         )->get;
      }

      1;
   };
}

sub test
{
   my ( $name, %params ) = @_;

   my $t = $output->enter_test( $name );

   my $success = _run_test( $t, %params );

   if( $success ) {
      $t->pass( $params{expect_fail} );
   }
   else {
      my $e = $@; chomp $e;
      $t->fail( $e, $params{expect_fail} );
      $params{expect_fail} ? $expected_fail++ : $failed++;
   }

   no warnings 'exiting';
   last TEST if $STOP_ON_FAIL and not $success and not $params{expect_fail};
}

sub prepare
{
   my ( $name, %params ) = @_;

   my @reqs;
   foreach my $req ( @{ $params{requires} || [] } ) {
      push @reqs, $test_environment{$req} and next if $test_environment{$req};

      $output->skip_prepare( $name, $req );
      return;
   }

   $output->start_prepare( $name );

   my $do = $params{do};
   my $success = eval {
      $do->( @reqs )->get;
      1;
   };

   if( $success ) {
      $output->pass_prepare;
   }
   else {
      my $e = $@; chomp $e;
      $output->fail_prepare( $e );
      $failed++;
   }

    no warnings 'exiting';
    last TEST if $STOP_ON_FAIL and not $success;
}

## Some assertion functions useful by test scripts. Put them in their own
#    package so that croak will find the correct line number
package assertions {
   use Carp;
   use Scalar::Util qw( looks_like_number );

   sub json_object_ok
   {
      my ( $obj ) = @_;
      ref $obj eq "HASH" or croak "Expected a JSON object";
   }

   sub json_keys_ok
   {
      my ( $obj, @keys ) = @_;
      json_object_ok( $obj );
      foreach ( @keys ) {
         defined $obj->{$_} or croak "Expected a '$_' key";
      }
   }

   sub json_list_ok
   {
      my ( $list ) = @_;
      ref $list eq "ARRAY" or croak "Expected a JSON list";
   }

   sub json_number_ok
   {
      my ( $num ) = @_;
      !ref $num and looks_like_number( $num ) or croak "Expected a JSON number";
   }

   sub json_string_ok
   {
      my ( $str ) = @_;
      !ref $str or croak "Expected a JSON string";
   }

   sub json_nonempty_string_ok
   {
      my ( $str ) = @_;
      !ref $str and length $str or croak "Expected a non-empty JSON string";
   }
}

{
   no strict 'refs';
   *$_ = \&{"assertions::$_"} for grep m/_ok/, keys %{"assertions::"};
}

TEST: {
   walkdir(
      sub {
         my ( $filename ) = @_;

         return unless basename( $filename ) =~ m/^\d+.*\.pl$/;

         $output->run_file( $filename );

         # Slurp and eval() the file instead of do() because then lexical
         # environment such as strict/warnings will still apply
         my $code = do {
            open my $fh, "<", $filename or die "Cannot read $filename - $!\n";
            local $/; <$fh>
         };

         # Tell eval what the filename is so we get nicer warnings/errors that
         # give the filename instead of (eval 123)
         eval( "#line 1 $filename\n" . $code . "; 1" ) or die $@;
      },
      "tests"
   );
}

if( $failed ) {
   $output->final_fail( $failed );
   exit 1;
}
else {
   $output->final_pass( $expected_fail );
   exit 0;
}

# Can't use File::Find because of the fact it always sorts directories after
# nondirectories, even if you give a sort function
#   https://rt.perl.org/Public/Bug/Display.html?id=122968
sub walkdir
{
   my ( $code, $path ) = @_;

   my @ents = do {
      opendir my $dirh, $path or die "Cannot opendir $path - $!";
      readdir $dirh;
   };

   foreach my $ent ( sort grep { not m/^\./ } @ents ) {
      my $subpath = "$path/$ent";
      if ( -d $subpath ) {
         walkdir( $code, $subpath );
      }
      else {
         $code->( $subpath );
      }
   }
}
