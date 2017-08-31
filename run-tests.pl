#!/usr/bin/env perl

use strict;
use warnings;
use 5.014; # package NAME { BLOCK }

use if $] >= 5.020, warnings => FATAL => "experimental";

use lib 'lib';

use SyTest::CarpByFile;
use SyTest::Assertions qw( :all );

use SyTest::JSONSensible;

use Future;
use Future::Utils qw( try_repeat repeat );
use IO::Async::Loop;

use Data::Dump qw( pp );
use File::Basename qw( basename );
use Getopt::Long qw( :config no_ignore_case gnu_getopt );
use IO::Socket::SSL;
use List::Util 1.33 qw( first all any maxstr max );
use Struct::Dumb 0.04;
use MIME::Base64 qw( decode_base64 );
use Time::HiRes qw( time );
use POSIX qw( strftime );

use Data::Dump::Filtered;
Data::Dump::Filtered::add_dump_filter( sub {
   Scalar::Util::refaddr($_[1]) == Scalar::Util::refaddr($IO::Async::Loop::ONE_TRUE_LOOP)
      ? { dump => '$IO::Async::Loop::ONE_TRUE_LOOP' }
      : undef;
});

use Module::Pluggable
   sub_name    => "output_formats",
   search_path => [ "SyTest::Output" ],
   require     => 1;

use Module::Pluggable
   sub_name    => "homeserver_factories",
   search_path => [ "SyTest::HomeserverFactory" ],
   require     => 1;

# A number of commandline arguments exist simply for passing values through to
# the way that the server is started by tests/05homeserver.pl. We'll collect
# them all in one place for neatness
our %SYNAPSE_ARGS = (
   directory  => "../synapse",
   python     => "python",
   extra_args => [],

   log        => 0,
   log_filter => [],
   coverage   => 0,
   dendron    => "",
);

our $WANT_TLS = 1;  # This is shared with the test scripts

our $BIND_HOST = "localhost";

# a unique ID for this test run. It is used in some tests to create user IDs
# and the like.
our $TEST_RUN_ID = strftime( '%Y%m%dT%H%M%S', gmtime() );

my %FIXED_BUGS;

my $STOP_ON_FAIL;
my $SERVER_IMPL = undef;

GetOptions(
   'I|server-implementation=s' => \$SERVER_IMPL,
   'C|client-log+' => \my $CLIENT_LOG,
   'S|server-log+' => \$SYNAPSE_ARGS{log},
   'server-grep=s' => \$SYNAPSE_ARGS{log_filter},
   'd|synapse-directory=s' => \$SYNAPSE_ARGS{directory},

   's|stop-on-fail' => sub { $STOP_ON_FAIL = 1 },
   'a|all'          => sub { $STOP_ON_FAIL = 0 },

   'O|output-format=s' => \(my $OUTPUT_FORMAT = "term"),

   'w|wait-at-end' => \my $WAIT_AT_END,

   'v|verbose+' => \(my $VERBOSE = 0),

   'n|no-tls' => sub { $WANT_TLS = 0 },

   'python=s' => \$SYNAPSE_ARGS{python},

   'coverage+' => \$SYNAPSE_ARGS{coverage},

   # these two are superceded by -I, but kept for backwards compat
   'dendron=s' => sub {
      $SERVER_IMPL = 'Synapse::ViaDendron' unless $SERVER_IMPL;
      $SYNAPSE_ARGS{dendron} = $_[1];
   },
   'haproxy'   => sub {
      $SERVER_IMPL = 'Synapse::ViaHaproxy' unless $SERVER_IMPL;
   },


   # These are now unused, but retaining arguments for commandline parsing support
   'pusher+'            => sub {},
   'synchrotron+'       => sub {},
   'federation-reader+' => sub {},
   'media-repository+'  => sub {},
   'appservice+'        => sub {},
   'federation-sender+' => sub {},
   'client-reader+'     => sub {},

   'bind-host=s' => \$BIND_HOST,

   'p|port-range=s' => \(my $PORT_RANGE = "8800:8899"),

   'F|fixed=s' => sub { $FIXED_BUGS{$_}++ for split m/,/, $_[1] },

   'E=s' => sub { # process -Eoption=value
      my @more = split m/=/, $_[1];

      # Turn single-letter into -X but longer into --NAME
      $_ = ( length > 1 ? "--$_" : "-$_" ) for $more[0];

      push @{ $SYNAPSE_ARGS{extra_args} }, @more;
   },

   'h|help' => sub { usage(0) },
) or usage(1);

my %only_files;
my $stop_after;
if( @ARGV ) {
   $only_files{$_}++ for @ARGV;

   $stop_after = maxstr keys %only_files;
}

if( $VERBOSE ) {
   push @{ $SYNAPSE_ARGS{extra_args} }, ( "-" . ( "v" x $VERBOSE ));
}

sub usage
{
   my ( $exitcode ) = @_;

   my @output_formats =
      map { $_->FORMAT }
      grep { $_->can( "FORMAT" ) } output_formats();

   my @homeserver_implementations =
      map { $_->name() } homeserver_factories();

   format STDERR =
run-tests.pl: [options...] [test-file]

Options:
   -I, --server-implementation  - specify the type of homeserver to start.
                                  Supported implementations:
                                   ~~ @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                      shift( @homeserver_implementations ) || ''

   -C, --client-log             - enable logging of requests made by the
                                  internal HTTP client. Also logs the internal
                                  HTTP server.

   -S, --server-log             - enable pass-through of server logs

       --server-grep PATTERN    - additionally, filter the server passthrough
                                  for matches of this pattern

   -d, --synapse-directory DIR  - path to the checkout directory of synapse

   -s, --stop-on-fail           - stop after the first failed test

   -a, --all                    - don't stop after the first failed test;
                                  attempt as many as possible

   -O, --output-format FORMAT   - set the style of test output report.
                                  Supported formats:
                                   ~~ @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                      shift( @output_formats ) || ''

   -w, --wait-at-end            - pause for input before shutting down testing
                                  synapse servers

   -v, --verbose                - increase the verbosity of output and
                                  synapse's logging level

   -n, --no-tls                 - prefer plaintext client connections where
                                  possible

       --python PATH            - path to the 'python' binary

       --coverage               - generate code coverage stats for synapse

   -p, --port-range START:MAX   - pool of TCP ports to allocate from

   -F, --fixed BUGS             - bug names that are expected to be fixed
                                  (ignores 'bug' declarations with these names)

   -ENAME,  -ENAME=VALUE        - pass extra argument NAME or NAME=VALUE

.

   write STDERR;
   exit $exitcode;
}

my $OUTPUT = first { $_->can( "FORMAT") and $_->FORMAT eq $OUTPUT_FORMAT } output_formats()
   or die "Unrecognised output format $OUTPUT_FORMAT\n";

$SERVER_IMPL = 'Synapse' unless $SERVER_IMPL;
my $hs_factory_class = first { $_->name() eq $SERVER_IMPL } homeserver_factories()
   or die "Unrecognised server implementation $SERVER_IMPL\n";
our $HS_FACTORY = $hs_factory_class -> new();

# Turn warnings into $OUTPUT->diag calls
$SIG{__WARN__} = sub {
   my $message = join "", @_;
   chomp $message;

   $OUTPUT->diagwarn( $message );
};

if( $CLIENT_LOG ) {
   require Net::Async::HTTP;
   require Net::Async::HTTP::Server;
   require Class::Method::Modifiers;
   require JSON;

   Class::Method::Modifiers::install_modifier( "Net::Async::HTTP",
      around => _do_request => sub {
         my ( $orig, $self, %args ) = @_;
         my $request = $args{request};

         my $request_uri = $request->uri;

         my $request_user = $args{request_user};

         my $original_on_redirect = $args{on_redirect};
         $args{on_redirect} = sub {
             my ( $response, $to ) = @_;
             print STDERR "\e[1;33mRedirect\e[m from ${ \$request->method } ${ \$request->uri->path }:\n";
             print STDERR "  $_\n" for split m/\n/, $response->as_string;
             print STDERR "-- \n";
             if ( $original_on_redirect ) {
                 $original_on_redirect->( $response, $to );
             }
         };

         if( $request_uri->path =~ m{/events$} ) {
            my %params = $request_uri->query_form;
            my $request_for = defined $request_user ? "user=$request_user" : "token=$params{access_token}";

            print STDERR "\e[1;32mPolling events\e[m",
               ( defined $params{from} ? " since $params{from}" : "" ) . " for $request_for\n";

            return $orig->( $self, %args )
               ->on_done( sub {
                  my ( $response ) = @_;

                  eval {
                     my $content_decoded = JSON::decode_json( $response->content );
                     my $events = $content_decoded->{chunk};
                     foreach my $event ( @$events ) {
                        print STDERR "\e[1;33mReceived event\e[m for ${request_for}:\n";
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
            my $request_for = defined $request_user ? " for user=$request_user" : "";

            print STDERR "\e[1;32mRequesting\e[m${request_for}:\n";
            print STDERR "  $_\n" for split m/\n/, $request->as_string;
            print STDERR "-- \n";

            return $orig->( $self, %args )
               ->on_done( sub {
                  my ( $response ) = @_;

                  print STDERR "\e[1;33mResponse\e[m from ${ \$request->method } ${ \$request->uri->path }${request_for}:\n";
                  print STDERR "  $_\n" for split m/\n/, $response->as_string;
                  print STDERR "-- \n";
               }
            );
         }
      }
   );

   Class::Method::Modifiers::install_modifier( "Net::Async::HTTP::Server",
      around => configure => sub {
         my ( $orig, $self, %args ) = @_;

         if( defined( my $on_request = $args{on_request} ) ) {
            $args{on_request} = sub {
               my ( undef, $request ) = @_;

               print STDERR "\e[1;32mReceived request\e[m:\n";
               print STDERR "  $_\n" for split m/\n/, $request->as_http_request->as_string;
               print STDERR "-- \n";

               return $on_request->( @_ );
            };
         }

         return $orig->( $self, %args );
      }
   );
   Class::Method::Modifiers::install_modifier( "Net::Async::HTTP::Server::Request",
      before => respond => sub {
         my ( $self, $response ) = @_;
         my $request_path = $self->path;

         print STDERR "\e[1;33mSending response\e[m to $request_path:\n";
         print STDERR "  $_\n" for split m/\n/, $response->as_string;
         print STDERR "-- \n";
      }
   );
}

my $loop = IO::Async::Loop->new;

# Be polite to any existing SIGINT handler (e.g. in case of Devel::MAT et.al.)
my $old_SIGINT = $SIG{INT};
$SIG{INT} = sub { $old_SIGINT->( "INT" ) if ref $old_SIGINT; exit 1 };

( my ( $port_next, $port_max ) = split m/:/, $PORT_RANGE ) == 2 or
   die "Expected a --port-range expressed as START:MAX\n";

my %port_desc;

## TODO: better name here
sub alloc_port
{
   my ( $desc ) = @_;
   defined $desc or croak "alloc_port() without description";

   die "No more free ports\n" if $port_next >= $port_max;
   my $port = $port_next++;

   $port_desc{$port} = $desc;

   return $port;
}

# Util. function for tests
sub delay
{
   my ( $secs ) = @_;
   $loop->delay_future( after => $secs );
}

# Handy utility wrapper around Future::Utils::try_repeat_until_success which
# includes a delay on retry
sub retry_until_success(&)
{
   my ( $code ) = @_;

   my $delay = 0.1;

   try_repeat {
      my $prev_f = shift;

      ( $prev_f ?
            delay( $delay *= 1.5 ) :
            Future->done )
         ->then( $code );
   }  until => sub { !$_[0]->failure };
}

# Another wrapper which repeats (with delay) until the block returns a true
# value. If the block fails entirely then it aborts, does not retry.
sub repeat_until_true(&)
{
   my ( $code ) = @_;

   my $delay = 0.1;

   repeat {
      my $prev_f = shift;

      ( $prev_f ?
            delay( $delay *= 1.5 ) :
            Future->done )
         ->then( $code );
   }  until => sub { $_[0]->get };
}

my @log_if_fail_lines;
my $test_start_time;

sub log_if_fail
{
   my ( $message, $structure ) = @_;

   my $elapsed_time = time() - $test_start_time;
   push @log_if_fail_lines, sprintf("%.06f: %s", $elapsed_time, $message);
   push @log_if_fail_lines, split m/\n/, pp( $structure ) if @_ > 1;
}

struct Fixture => [qw( name requires start result teardown )], predicate => "is_Fixture";

my $fixture_count = 0;
sub fixture
{
   my %args = @_;

   # make up an id for later labelling etc
   my $count = $fixture_count++;
   my $name = $args{name} // "FIXTURE-$count";

   my $setup = $args{setup} or croak "fixture needs a 'setup' block";
   ref( $setup ) eq "CODE" or croak "Expected fixture 'setup' block to be CODE";

   my $teardown = $args{teardown};
   !$teardown || ref( $teardown ) eq "CODE" or croak "Expected fixture 'teardown' to be CODE";

   my @req_futures;
   my $f_start = Future->new;

   my @requires;
   foreach my $req ( @{ $args{requires} // [] } ) {
      if( is_Fixture( $req ) ) {
         push @requires, @{ $req->requires };
         push @req_futures, $f_start->then( sub {
            my ( $env ) = @_;

            $req->start->( $env );
            $req->result;
         })->set_label( "$name->" . $req->name );
      }
      else {
         push @requires, $req;
         push @req_futures, $f_start->then( sub {
            my ( $proven ) = @_;

            $proven->{$req} or die "TODO: Missing fixture dependency $req\n";
            Future->done;
         });
      }
   }

   # If there's no requirements, we still want to wait for $f_start before we
   # actually invoke $setup
   @req_futures or push @req_futures, $f_start;

   return Fixture(
      $name,

      \@requires,

      sub { $f_start->done( @_ ) unless $f_start->is_ready },

      Future->needs_all( @req_futures )
         ->then( $setup )
         ->set_label( $name ),

      $teardown ? sub {
         my ( $self ) = @_;
         my $result_f = $self->result;

         $self->result = Future->fail(
            "This Fixture has been torn down and cannot be used again"
         );

         if( $result_f->is_ready ) {
            return $teardown->( $result_f->get );
         }
         else {
            $result_f->cancel;
            Future->done;
         }
      } : undef,
   );
}

use constant { PROVEN => 1, PRESUMED => 2 };
my %proven;

our $MORE_STUBS;

sub maybe_stub
{
   my ( $f ) = @_;
   my $failmsg = SyTest::CarpByFile::shortmess( "Stub" );

   $MORE_STUBS or
      croak "Cannot declare a stub outside of a test";

   push @$MORE_STUBS, $f->on_fail( sub {
      my ( $failure ) = @_;
      die "$failmsg $failure";
   });
}

sub require_stub
{
   my ( $f ) = @_;
   my $failmsg = SyTest::CarpByFile::shortmess( "Required stub never happened" );

   maybe_stub $f->on_cancel( sub {
      die $failmsg;
   });
}

struct Test => [qw(
   file name multi expect_fail critical proves requires check do timeout
)];

my @TESTS;

sub _push_test
{
   my ( $filename, $multi, $name, %params ) = @_;

   # We expect this test to fail if it's declared to be dependent on a bug that
   # is not yet fixed
   $params{expect_fail}++ if $params{bug} and not $FIXED_BUGS{ $params{bug} };

   if( %only_files and not exists $only_files{$filename} ) {
      $proven{$_} = PRESUMED for @{ $params{proves} // [] };
      return;
   }

   push @TESTS, Test( $filename, $name, $multi,
      @params{qw( expect_fail critical proves requires check do timeout )} );
}

sub _run_test
{
   my ( $t, $test ) = @_;

   undef @log_if_fail_lines;
   $test_start_time = time();

   local $MORE_STUBS = [];

   my @requires = @{ $test->requires // [] };

   my $f_start = Future->new;
   my @req_futures;

   foreach my $req ( @requires ) {
      if( is_Fixture( $req ) ) {
         my $fixture = $req;

         push @req_futures, $f_start->then( sub {
            $fixture->start->( \%proven );
            $fixture->result;
         })->set_label( "run_test->" . $fixture->name );
      }
      else {
         if( !exists $proven{$req} ) {
            $t->skip( "lack of $req" );
            return;
         }
         $OUTPUT->diag( "Presuming ability '$req'" ) if $proven{$req} == PRESUMED;
      }
   }

   $t->start;
   $f_start->done;

   my $success = eval {
      my @reqs;
      my $f_setup = Future->needs_all( @req_futures )
         ->on_done( sub { @reqs = @_ } )
         ->on_fail( sub { die "fixture failed - $_[0]\n" } );

      my $f_test = $f_setup;

      my $check = $test->check;
      if( my $do = $test->do ) {
         if( $check ) {
            $f_test = $f_test->then( sub {
               Future->wrap( $check->( @reqs ) )
            })->followed_by( sub {
               my ( $f ) = @_;

               $f->failure or
                  warn "Warning: ${\$t->name} was already passing before we did anything\n";

               Future->done;
            });
         }

         $f_test = $f_test->then( sub {
            Future->wrap( $do->( @reqs ) )
         });
      }

      if( $check ) {
         $f_test = $f_test->then( sub {
            Future->wrap( $check->( @reqs ) )
         })->then( sub {
            my ( $result ) = @_;
            $result or
               die "Test check function failed to return a true value";

            Future->done;
         });
      }

      Future->wait_any(
         $f_setup,
         $loop->delay_future( after => 60 )
            ->then_fail( "Timed out waiting for setup" )
      )->get;

      Future->wait_any(
         $f_test,

         $loop->delay_future( after => $test->timeout // 10 )
            ->then_fail( "Timed out waiting for test" )
      )->get;

      foreach my $stub_f ( @$MORE_STUBS ) {
         $stub_f->cancel;
      }

      1;
   };

   Future->needs_all( map {
      if( is_Fixture( $_ ) and $_->teardown ) {
         $_->teardown->( $_ );
      }
      else {
         ();
      }
   } @requires )->get;

   if( $success ) {
      $proven{$_} = PROVEN for @{ $test->proves // [] };
      $t->pass;
   }
   else {
      my $e = $@; chomp $e;
      $t->fail( $e );
   }
}

our $RUNNING_TEST;

sub pass
{
   my ( $testname ) = @_;
   $RUNNING_TEST->ok( 1, $testname );
}

# A convenience for the otherwise-common pattern of
#   ->on_done( sub { pass $message } )
sub SyTest::pass_on_done
{
   my $self = shift;
   my ( $message ) = @_;
   $self->on_done( sub { $RUNNING_TEST->ok( 1, $message ) } );
}

sub list_symbols
{
   my ( $pkg ) = @_;

   no strict 'refs';
   return grep { $_ !~ m/^_</ and $_ !~ m/::$/ }  # filter away filename markers and sub-packages
          keys %{$pkg."::"};
}

TEST: {
   walkdir(
      sub {
         my ( $filename ) = @_;

         return unless basename( $filename ) =~ m/\.pl$/;

         no warnings 'once';

         local *test       = sub { _push_test( $filename, 0, @_ ); };
         local *multi_test = sub { _push_test( $filename, 1, @_ ); };

         # Slurp and eval() the file instead of do() because then lexical
         # environment such as strict/warnings will still apply
         my $code = do {
            open my $fh, "<", $filename or die "Cannot read $filename - $!\n";
            local $/; <$fh>
         };

         # Protect against symbolic leakage between test files by cleaning up
         # extra symbols in the 'main::' namespace
         my %was_symbs = map { $_ => 1 } list_symbols( "main" );

         # Tell eval what the filename is so we get nicer warnings/errors that
         # give the filename instead of (eval 123)
         eval( "#line 1 $filename\n" . $code . "; 1" ) or die $@;

         {
            no strict 'refs';

            # Occasionally we *do* want to export a symbol.
            $was_symbs{$_}++ for @{"main::EXPORT"};

            $was_symbs{$_} or delete ${"main::"}{$_} for list_symbols( "main" );
         }

         no warnings 'exiting';
         last TEST if $stop_after and $filename eq $stop_after;
      },
      "tests"
   );
}

my $done_count = 0;
my $failed_count = 0;
my $expected_fail_count = 0;
my $skipped_count = 0;

$OUTPUT->status(
   tests   => scalar @TESTS,
   done    => $done_count,
   failed  => $failed_count,
   skipped => $skipped_count,
);

# Now run the tests
my $prev_filename;
foreach my $test ( @TESTS ) {
   if( !$prev_filename or $prev_filename ne $test->file ) {
      $OUTPUT->run_file( $prev_filename = $test->file );
   }

   my $m = $test->multi ? "enter_multi_test" : "enter_test";

   my $t = $OUTPUT->$m( $test->name, $test->expect_fail );
   local $RUNNING_TEST = $t;

   _run_test( $t, $test );

   $t->leave;

   $done_count++;

   if( $t->skipped ) {
      $skipped_count++;
   }

   if( $t->failed ) {
      $test->expect_fail ? $expected_fail_count++ : $failed_count++;

      $OUTPUT->diag( $_ ) for @log_if_fail_lines;

      last if $STOP_ON_FAIL and not $test->expect_fail;

      if( $test->critical ) {
         warn "This CRITICAL test has failed - bailing out\n";
         last;
      }
   }

   $OUTPUT->status(
      tests   => scalar @TESTS,
      done    => $done_count,
      failed  => $failed_count,
      skipped => $skipped_count,
   );
}

$OUTPUT->status();

if( $WAIT_AT_END ) {
   ## It's likely someone wants to interact with a running system. Lets print all
   #    the port descriptions to be useful
   my $width = max map { length } values %port_desc;

   print STDERR "\n";
   printf STDERR "%-*s: %d\n", $width, $port_desc{$_}, $_ for sort keys %port_desc;

   print STDERR "Waiting... (hit ENTER to end)\n";
   $loop->add( my $stdin = IO::Async::Stream->new_for_stdin( on_read => sub {} ) );
   $stdin->read_until( "\n" )->get;
}

# A workaround for
#   https://rt.perl.org/Public/Bug/Display.html?id=128774
my @AT_END;
sub AT_END
{
   push @AT_END, @_;
}

$_->() for @AT_END;

if( $failed_count ) {
   $OUTPUT->final_fail( $failed_count );

   # TODO: umh.. this apparently broke some time ago. Should fix it
   #my @f;
   #foreach my $synapse ( @{ $test_environment{synapses} } ) {
   #   $synapse->print_output;
   #   push @f, $synapse->await_finish;
   #
   #   $synapse->kill( 'INT' );
   #}

   #Future->wait_all( @f )->get if @f;
   exit 1;
}
else {
   $OUTPUT->final_pass( $expected_fail_count, $skipped_count );
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
