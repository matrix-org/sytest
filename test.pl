#!/usr/bin/perl

use strict;
use warnings;
use 5.010;

use lib 'lib';

use Carp;

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

# Some tests create objects as a side-effect that later tests will depend on,
# such as clients, users, rooms, etc... These are called the Environment
my %test_environment;
sub provide
{
   my ( $name, $value ) = @_;
   exists $test_environment{$name} and
      carp "Overwriting existing test environment key '$name'";

   $test_environment{$name} = $value;
}

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

my @clients = Future->needs_all(
   map {
      my $port = $_;

      my $matrix = SyTest::MatrixClient->new(
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

      Future->done( $matrix );
   } @PORTS
)->get;

$test_environment{clients} = \@clients;

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
   }

   foreach my $req ( $test->provides ) {
      exists $test_environment{$req} and next;

      print "\e[1;31mWARN\e[m: Test failed to provide the '$req' environment as promised\n";
   }
}

package TestCase {
   sub new { my $class = shift; bless { @_ }, $class }

   sub name { shift->{name} }
   sub file { shift->{file} }

   sub requires { @{ shift->{requires} || [] } }
   sub provides { @{ shift->{provides} || [] } }

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
