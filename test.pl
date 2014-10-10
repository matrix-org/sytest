#!/usr/bin/perl

use strict;
use warnings;
use 5.010;

use lib 'lib';

use Future;
use IO::Async::Loop;

use Test::More;
use IO::Async::Test;

use Data::Dump qw( pp );
use Getopt::Long;
use IO::Socket::SSL;
use List::Util qw( all );
use POSIX qw( strftime );

use SyTest::Synapse;
use SyTest::MatrixClient;

GetOptions(
   'N|number=i'    => \(my $NUMBER = 2),
   'C|client-log+' => \my $CLIENT_LOG,
   'S|server-log+' => \my $SERVER_LOG,
) or exit 1;

if( $CLIENT_LOG ) {
   require Net::Async::HTTP;
   require Class::Method::Modifiers;

   Class::Method::Modifiers::install_modifier( "Net::Async::HTTP",
      around => _do_request => sub {
         my ( $orig, $self, %args ) = @_;
         my $request = $args{request};

         my $request_uri = $request->uri;
         return $orig->( $self, %args ) if $request_uri->path =~ m{/events$};

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
   );

   Class::Method::Modifiers::install_modifier( "Net::Async::Matrix",
      before => _incoming_event => sub {
         my ( $self, $event ) = @_;

         print STDERR "\e[1;33mReceived event\e[m from $self->{server}:\n";
         print STDERR "  $_\n" for split m/\n/, pp( $event );
         print STDERR "-- \n";
      }
   );
}

my $loop = IO::Async::Loop->new;
testing_loop( $loop );

my @tests;

use File::Basename qw( basename );
use File::Find;
find({
   no_chdir => 1,
   preprocess => sub { sort @_ },
   wanted => sub {
      return unless basename( $_ ) =~ m/^\d+.*\.pl$/;
      print "Loading $_\n";

      no warnings 'once';
      local *test = sub {
         my ( $name, %parts ) = @_;
         push @tests, TestCase->new(
            name => $name,
            file => $_,
            %parts,
         );
      };

      # This is hideous
      do $File::Find::name or
         die $@ || "Cannot 'do $_' - $!";
   }},
   "tests"
);

# Terribly useful
sub Future::on_done_diag {
   my ( $self, $message ) = @_;
   $self->on_done( sub { diag( $message ) } );
}

# Start up 3 homeservers

my %synapses_by_port;
END {
   print STDERR "Killing synapse servers...\n" if %synapses_by_port;
   print STDERR "[${\$_->pid}] " and kill INT => $_->pid for values %synapses_by_port;
   print STDERR "\n";
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

Future->needs_all(
   map {
      my $port = $_;

      my $matrix = $clients_by_port{$port} = SyTest::MatrixClient->new(
         server => "localhost",
         port   => $port,
         SSL    => 1,
         SSL_verify_mode => SSL_VERIFY_NONE,

         on_error => sub {
            my ( $self, $failure, $name, @args ) = @_;

            die $failure unless $name and $name eq "http";
            my ( $response, $request ) = @args;

            print STDERR "Received from " . $request->uri . "\n";
            if( defined $response ) {
               print STDERR "  $_\n" for split m/\n/, $response->as_string;
            }
            else {
               print STDERR "No response\n";
            }

            die $failure;
         },
      );

      $loop->add( $matrix );
      $matrix->register( user_id => "u-$port", password => "f00b4r" )
         ->on_done_diag( "Registered user u-$port" )
         ->then( sub { $matrix->start } )
         ->on_done_diag( "Started event stream for u-$port" )
   } @PORTS
)->get;

# Some tests create objects as a side-effect that later tests will depend on,
# such as clients, users, rooms, etc... These are called the Environment
my %test_environment;

# For now, declare the clients as env
$test_environment{clients} = [ @clients_by_port{@PORTS} ];

## NOW RUN THE TESTS
TEST: foreach my $test ( @tests ) {
   my @params;
   foreach my $req ( $test->requires ) {
      push @params, $test_environment{$req} and next if $test_environment{$req};

      print "\e[1;33mSKIP\e[m ${\$test->name} (${\$test->file}) due to lack of $req\n";
      next TEST;
   }

   print "\e[36mTesting if: ${\$test->name} (${\$test->file})\e[m... ";
   if( eval { $test->run( @params ); 1 } ) {
      print "\e[32mPASS\e[m\n";
   }
   else {
      my $e = $@; chomp $e;
      print "\e[1;31mFAIL\e[m:\n";
      print " | $_\n" for split m/\n/, $e;
      print " +----------------------\n";
      # TODO: work out what else to skip
   }
}

# Now use one of the clients to create a room and the rest to join it
my ( $first_client, @remaining_clients ) = @clients_by_port{@PORTS};
my ( $FIRST_PORT, @REMAINING_PORTS ) = @PORTS;

my $ROOM = "test-room";

my %rooms_by_port;        # {$port} = $room
( $rooms_by_port{$FIRST_PORT}, my $room_alias ) = $first_client->create_room( $ROOM )
   ->get;
diag( "Created $room_alias" );

@rooms_by_port{@REMAINING_PORTS} = Future->needs_all(
   map {
      $clients_by_port{$_}->join_room( $room_alias )
         ->on_done_diag( "Joined $room_alias" )
   } @REMAINING_PORTS
)->get;

diag( "Now all users should be in the room" );

my %roommembers_by_port;  # {$port}{$user_id} = $membership
my %roommessages_by_port; # {$port} = \@messages

sub on_room_member
{
   my ( $port, $room, $member, %changes ) = @_;
   my $user = $member->user;

   $roommembers_by_port{$port}{$member->user->user_id} = $member->membership;

   no warnings 'uninitialized';

   $changes{membership} and
      print qq(\e[1;36m[$port]\e[m >> "${\$member->displayname}" in "${\$room->room_id}" membership state ${\$member->membership} (was $changes{membership}[0])\n);
   $changes{presence} and
      print qq(\e[1;36m[$port]\e[m >> "${\$member->displayname}" in "${\$room->room_id}" presence state ${\$user->presence} (was $changes{presence}[0])\n);
   $changes{last_active} and
      print qq(\e[1;36m[$port]\e[m >> "${\$member->displayname}" was last active at ${\strftime "%Y/%m/%d %H:%M:%S", localtime $user->last_active}\n);
}

foreach my $port ( keys %rooms_by_port ) {
   my $room = $rooms_by_port{$port};

   $roommessages_by_port{$port} = [];

   $room->configure(
      on_membership => sub {
         my $room = shift;
         my ( $member, $event, $subject_member, %changes ) = @_;
         on_room_member( $port, $room, $subject_member, %changes );
      },
      on_presence   => sub {
         my $room = shift;
         my $member = shift;
         on_room_member( $port, $room, $member, @_ );
      },
      on_message => sub {
         my ( $room, $member, $content ) = @_;
         print qq(\e[1;36m[$port]\e[m >> "${\$member->displayname}" in "${\$room->room_id}" sends message $content->{msgtype}\n);

         # Timestamps are icky to test. Delete them
         delete $content->{hsob_ts};
         delete $content->{hsib_ts};

         push @{ $roommessages_by_port{$port} }, $content;
      },
   );

   # Fetch initial members after sync
   $room->initial_sync->get;

   foreach my $member ( $room->members ) {
      my %changes = map { $_ => [ undef, $member->$_ ] } qw( membership );
      on_room_member( $port, $room, $member, %changes );
   }
}

wait_for {
   $NUMBER == keys %roommembers_by_port and
      all { $NUMBER == keys %$_ } values %roommembers_by_port;
};
is_deeply( \%roommembers_by_port,
   { map {
      my $port = $_;
      $port => { map {; "\@u-$_:localhost:$_" => "join" } @PORTS }
     } @PORTS },
   '%members_by_port after all other clients ->join_room' );

wait_for {
   all { $NUMBER == keys %{ $clients_by_port{$_}->cached_presence } } @PORTS;
};
is_deeply(
   # Each user should now see everyone's presence as online
   { map { $_ => $clients_by_port{$_}->cached_presence } @PORTS },
   { map {
      my $port = $_;
      $port => { map {; "\@u-$_:localhost:$_" => "online" } @PORTS }
     } @PORTS },
   'cached_presence after ->join_room'
);

sub flush
{
   diag( "Waiting 3 seconds for messages to flush" );
   $loop->delay_future( after => 3 )->get;
}

flush();

diag( "Setting ${\$first_client->myself->displayname} away" );

$first_client->set_presence( unavailable => "Gone testin'" )->get;
flush();

is_deeply(
   # Each user should now see first port's presence as unavailable
   { map { $_ => $clients_by_port{$_}->cached_presence } @PORTS },
   { map {
      my $port = $_;
      $port => { map {;
         "\@u-$_:localhost:$_" => ( $_ == $FIRST_PORT ) ? "unavailable" : "online"
      } @PORTS }
     } @PORTS },
   'cached_presence after ->join_room' );

$rooms_by_port{$FIRST_PORT}->send_message( "Here is a message" )->get;

wait_for {
   all { scalar @{ $roommessages_by_port{$_} } } @PORTS
};
is_deeply(
   # Each user should now see the message
   { map {
      my $port = $_;
      $port => [
         { msgtype => "m.text", body => "Here is a message" }
      ]
   } @PORTS },
   \%roommessages_by_port,
   '%roommessages_by_port' );

flush();

done_testing;

package TestCase {
   sub new { my $class = shift; bless { @_ }, $class }

   sub name { shift->{name} }
   sub file { shift->{file} }

   sub requires { @{ shift->{requires} || [] } }

   sub run
   {
      my $self = shift;
      my ( @params ) = @_;

      my $check = $self->{check};

      if( my $do = $self->{do} ) {
         if( $check ) {
            eval { $check->( @params )->get } and
               warn "Warning: ${\$self->name} was already passing before we did anything\n";
         }

         $do->( @params )->get;
      }

      if( $check ) {
         my $attempts = $self->{wait_time} // 0;
         do {
            eval {
               $check->( @params )->get or
                  die "Test check function failed to return a true value"
            } and return 1;
            die "$@" unless $attempts;

            print "wait...\n";
            $loop->delay_future( after => 1 )->get;
            $attempts--;
         } while(1);
      }

      return 1;
   }
}
