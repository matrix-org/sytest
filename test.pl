#!/usr/bin/perl

use strict;
use warnings;
use 5.010;

use lib 'lib';

use Future;
use IO::Async::Loop;
use Net::Async::Matrix;

use Test::More;
use IO::Async::Test;

use Data::Dump qw( pp );
use Getopt::Long;
use List::Util qw( all );

use SyTest::Synapse;

GetOptions(
   'N|number=i'    => \(my $NUMBER = 2),
   'C|client-log+' => \my $CLIENT_LOG,
   'S|server-log+' => \my $SERVER_LOG,
) or exit 1;

if( $CLIENT_LOG ) {
   require Net::Async::HTTP;
   require Class::Method::Modifiers;

   Class::Method::Modifiers::install_modifier( "Net::Async::HTTP",
      after => prepare_request => sub {
         my ( $self, $request ) = @_;

         print STDERR "\e[1;32mSending\e[m:\n";
         print STDERR "  $_\n" for split m/\n/, $request->as_string;
         print STDERR "-- \n";
      }
   );

   Class::Method::Modifiers::install_modifier( "Net::Async::HTTP",
      before => process_response => sub {
         my ( $self, $response ) = @_;
         my $request_uri = $response->request->uri;

         print STDERR "\e[1;33mReceived\e[m from $request_uri:\n";
         print STDERR "  $_\n" for split m/\n/, $response->as_string;
         print STDERR "-- \n";
      }
   );
}

my $loop = IO::Async::Loop->new;
testing_loop( $loop );

# Terribly useful
sub Future::on_done_diag {
   my ( $self, $message ) = @_;
   $self->on_done( sub { diag( $message ) } );
}

# Start up 3 homeservers

my %synapses_by_port;
END {
   print STDERR "Killing synapse servers...\n" if %synapses_by_port;
   kill INT => $_->pid for values %synapses_by_port;
}
$SIG{INT} = sub { exit 1 };

my @PORTS = 8001 .. 8000+$NUMBER;
my @f;
foreach my $port ( @PORTS ) {
   my $synapse = $synapses_by_port{$port} = SyTest::Synapse->new(
      synapse_dir  => "../synapse",
      port         => $port,
      print_output => $SERVER_LOG,
   );
   $loop->add( $synapse );

   push @f, Future->wait_any(
      $synapse->started_future
         ->on_done_diag( "Synapse on port $port now listening" ),

      $loop->delay_future( after => 10 )
         ->then_fail( "Synapse server on port $port failed to start" ),
   );
}

Future->needs_all( @f )->get;

# Now lets create some users. 1 user per HS for now

my %clients_by_port;  # {$port} = $matrix
my %presence_by_port; # {$port}{$user_id} = $presence
my %members_by_port;  # {$port}{$user_id} = $membership

Future->needs_all(
   map {
      my $port = $_;

      my $matrix = $clients_by_port{$port} = Net::Async::Matrix->new(
         server => "localhost:$port",
         path_prefix => "_matrix/client/api/v1",

         on_error => sub {
            my ( $self, $failure, $name, @args ) = @_;

            die $failure unless $name eq "http";
            my ( $response, $request ) = @args;

            print STDERR "Received from " . $request->uri . "\n";
            print STDERR "  $_\n" for split m/\n/, $response->as_string;

            die $failure;
         },

         on_presence => sub {
            my ( $matrix, $user, %changes ) = @_;
            $presence_by_port{$port}{$user->user_id} = $user->presence;
            print qq(\e[1;36m[$port]\e[m >> "${\$user->displayname}" presence state ${\$user->presence}\n);
         },

         on_room_member => sub {
            my ( $room, $member, %changes ) = @_;
            $members_by_port{$port}{$member->user_id} = $member->membership;

            $changes{membership} and
               print qq(\e[1;36m[$port]\e[m >> "${\$member->displayname}" in "${\$room->room_id}" membership state ${\$member->membership}\n);
            $changes{presence} and
               print qq(\e[1;36m[$port]\e[m >> "${\$member->displayname}" in "${\$room->room_id}" presence state ${\$member->presence}\n);
         },
      );

      $loop->add( $matrix );
      $matrix->register( "u-$port" )
         ->on_done_diag( "Registered user u-$port" )
         ->then( sub { $matrix->start } )
         ->on_done_diag( "Started event stream for u-$port" )
   } @PORTS
)->get;

# Each user could do with a displayname
Future->needs_all(
   map {
      my $port = $_;
      $clients_by_port{$port}->set_displayname( "User on $port" )
         ->on_done_diag( "Set User $port displayname" )
   } keys %clients_by_port
)->get;

wait_for { $NUMBER == keys %presence_by_port };
is_deeply( \%presence_by_port,
   # Each user should initially only see their own presence state
   { map { $_ => { "\@u-$_:localhost:$_" => "online" } } @PORTS },
   '%presence_by_port after *->set_displayname' );

# Now use one of the clients to create a room and the rest to join it
my ( $first_client, @remaining_clients ) = @clients_by_port{@PORTS};
my ( $FIRST_PORT ) = @PORTS;

my $ROOM = "test-room";

my ( undef, $room_alias ) = $first_client->create_room( $ROOM )
   ->get;
diag( "Created $room_alias" );

wait_for { keys %members_by_port };
is_deeply( \%members_by_port,
   { $FIRST_PORT => { "\@u-$FIRST_PORT:localhost:$FIRST_PORT" => "join" } },
   '%members_by_port after first client ->create_room' );

Future->needs_all(
   map {
      $_->join_room( $room_alias )
         ->on_done_diag( "Joined $room_alias" )
   } @remaining_clients
)->get;

diag( "Now all users should be in the room" );

wait_for {
   $NUMBER == keys %members_by_port and
      all { $NUMBER == keys %$_ } values %members_by_port;
};
is_deeply( \%members_by_port,
   { map {
      my $port = $_;
      $port => { map {; "\@u-$_:localhost:$_" => "join" } @PORTS }
     } @PORTS },
   '%members_by_port after all other clients ->join_room' );

wait_for {
   $NUMBER == keys %presence_by_port and
      all { $NUMBER == keys %$_ } values %presence_by_port;
};
is_deeply( \%presence_by_port,
   # Each user should now see everyone's presence as online
   { map {
      my $port = $_;
      $port => { map {; "\@u-$_:localhost:$_" => "online" } @PORTS }
     } @PORTS },
   '%presence_by_port after ->join_room' );

sub flush
{
   diag( "Waiting 3 seconds for messages to flush" );
   $loop->delay_future( after => 3 )->get;
}

flush();

diag( "Setting ${\$first_client->myself->displayname} away" );

$first_client->set_presence( unavailable => "Gone testin'" )->get;
flush();

is_deeply( \%presence_by_port,
   # Each user should now see first port's presence as unavailable
   { map {
      my $port = $_;
      $port => { map {;
         "\@u-$_:localhost:$_" => ( $_ == $FIRST_PORT ) ? "unavailable" : "online"
      } @PORTS }
     } @PORTS },
   '%presence_by_port after ->join_room' );

done_testing;
