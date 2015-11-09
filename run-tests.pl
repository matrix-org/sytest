#!/usr/bin/env perl

use strict;
use warnings;
use 5.014; # package NAME { BLOCK }

use if $] >= 5.020, warnings => FATAL => "experimental";

use lib 'lib';

use SyTest::CarpByFile;

use Future;
use IO::Async::Loop;

use Data::Dump qw( pp );
use File::Basename qw( basename );
use Getopt::Long qw( :config no_ignore_case gnu_getopt );
use IO::Socket::SSL;
use JSON;
use List::Util 1.33 qw( first all any maxstr );
use Struct::Dumb 0.04;
use MIME::Base64 qw( decode_base64 );

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

# A number of commandline arguments exist simply for passing values through to
# the way that synapse is started by tests/05synapse.pl. We'll collect them
# all in one place for neatness
my %SYNAPSE_ARGS = (
   directory  => "../synapse",
   python     => "python",
   extra_args => [],

   log        => 0,
   log_filter => [],
   coverage   => 0,
);

my $WANT_TLS = 1;
my %FIXED_BUGS;

my $STOP_ON_FAIL;

GetOptions(
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

   'p|port-base=i' => \(my $PORT_BASE = 8000),

   'F|fixed=s' => sub { $FIXED_BUGS{$_}++ for split m/,/, $_[1] },

   'E=s' => sub { # process -Eoption=value
      my @more = split m/=/, $_[1];

      # Turn single-letter into -X but longer into --NAME
      $_ = ( length > 1 ? "--$_" : "-$_" ) for $more[0];

      push @{ $SYNAPSE_ARGS{extra_args} }, @more;
   },

   'h|help' => sub { usage(0) },
) or usage(1);

push @{ $SYNAPSE_ARGS{extra_args} }, "-v" if $VERBOSE;

sub usage
{
   my ( $exitcode ) = @_;

   print STDERR <<'EOF';
run-tests.pl: [options...] [test-file]

Options:
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

   -O, --output-format FORMAT   - set the style of test output report

   -w, --wait-at-end            - pause for input before shutting down testing
                                  synapse servers

   -v, --verbose                - increase the verbosity of output and
                                  synapse's logging level

   -n, --no-tls                 - prefer plaintext client connections where
                                  possible

       --python PATH            - path to the 'python' binary

       --coverage               - generate code coverage stats for synapse

   -p, --port-base NUMBER       - initial port number to run server under test

   -F, --fixed BUGS             - bug names that are expected to be fixed
                                  (ignores 'bug' declarations with these names)

   -ENAME,  -ENAME=VALUE        - pass extra argument NAME or NAME=VALUE

EOF

   exit $exitcode;
}

my $output = first { $_->can( "FORMAT") and $_->FORMAT eq $OUTPUT_FORMAT } output_formats()
   or die "Unrecognised output format $OUTPUT_FORMAT\n";

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

$SIG{INT} = sub { exit 1 };


# Some tests create objects as a side-effect that later tests will depend on,
# such as clients, users, rooms, etc... These are called the Environment
my %test_environment = (
   synapse_args => \%SYNAPSE_ARGS,

   # We need two servers; a "local" and a "remote" one for federation-based tests
   synapse_ports => [ $PORT_BASE + 1, $PORT_BASE + 2 ],

   want_tls => $WANT_TLS,
);

our @PROVIDES;

sub provide
{
   my ( $name, $value ) = @_;
   exists $test_environment{$name} and
      carp "Overwriting existing test environment key '$name'";
   any { $name eq $_ } @PROVIDES or
      carp "Was not expecting to provide '$name'";

   $test_environment{$name} = $value;
}

sub unprovide
{
   my @names = @_;

   delete $test_environment{$_} for @names;
}

# Util. function for tests
sub delay
{
   my ( $secs ) = @_;
   $loop->delay_future( after => $secs );
}

my @log_if_fail_lines;

sub log_if_fail
{
   my ( $message, $structure ) = @_;

   push @log_if_fail_lines, $message;
   push @log_if_fail_lines, split m/\n/, pp( $structure ) if @_ > 1;
}

struct Fixture => [qw( requires start result teardown )], predicate => "is_Fixture";

sub fixture
{
   my %args = @_;

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
         });
      }
      else {
         push @requires, $req;
         push @req_futures, $f_start->then( sub {
            my ( $env ) = @_;

            exists $env->{$req} or die "TODO: Missing fixture dependency $req\n";
            Future->done( $env->{$req} );
         });
      }
   }

   return Fixture(
      \@requires,

      sub { $f_start->done( @_ ) unless $f_start->is_ready },

      Future->needs_all( @req_futures )
         ->then( $setup ),

      $teardown ? sub {
         my ( $self ) = @_;

         if( $self->result->is_ready ) {
            return $teardown->( $self->result->get );
         }
         else {
            $self->result->cancel;
            Future->done;
         }
      } : undef,
   );
}

my $failed;
my $expected_fail;
my $skipped_count = 0;

our $SKIPPING;

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

sub _run_test
{
   my ( $t, %params ) = @_;

   # We expect this test to fail if it's declared to be dependent on a bug that
   # is not yet fixed
   $params{expect_fail}++ if $params{bug} and not $FIXED_BUGS{ $params{bug} };

   undef @log_if_fail_lines;

   local @PROVIDES = @{ $params{provides} || [] };
   local $MORE_STUBS = [];

   # If the test doesn't provide anything, and we're in skipping mode, just stop right now
   if( $SKIPPING and !@PROVIDES ) {
      $t->skipped++;
      return;
   }

   my @requires = @{ $params{requires} || [] };

   my $f_start = Future->new;
   my @req_futures;

   foreach my $req ( @requires ) {
      if( is_Fixture( $req ) ) {
         my $fixture = $req;

         exists $test_environment{$_} or die "TODO: Missing fixture dependency $_"
            for @{ $fixture->requires };

         push @req_futures, $f_start->then( sub {
            $fixture->start->( \%test_environment );
            $fixture->result;
         });
      }
      else {
         if( !exists $test_environment{$req} ) {
            $t->skip( "lack of $req" );
            return;
         }

         # Fetch its value immediately
         push @req_futures, Future->done( $test_environment{$req} );
      }
   }

   $t->start;
   $f_start->done;

   my $success = eval {
      my @reqs;
      my $f_test = Future->needs_all( @req_futures )
         ->on_done( sub { @reqs = @_ } )
         ->on_fail( sub { die "fixture failed - $_[0]\n" } );

      my $check = $params{check};
      if( my $do = $params{do} ) {
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

      if( my $await = $params{await} ) {
         die "TODO: 'await' now dead";
      }

      Future->wait_any(
         $f_test,

         $loop->delay_future( after => $params{timeout} // 10 )
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
      exists $test_environment{$_} or warn "Test step ${\$t->name} did not provide a value for $_\n"
         for @PROVIDES;

      $t->pass;
   }
   else {
      my $e = $@; chomp $e;
      $t->fail( $e );
   }

   if( $t->failed ) {
      $params{expect_fail} ? $expected_fail++ : $failed++;
   }
}

sub test
{
   my ( $name, %params ) = @_;

   my $t = $output->enter_test( $name, $params{expect_fail} );
   _run_test( $t, %params );
   $t->leave;

   if( $t->failed ) {
      $output->diag( $_ ) for @log_if_fail_lines;
   }
   if( $t->skipped ) {
      $skipped_count++;
   }

   if( $t->failed ) {
      no warnings 'exiting';

      last TEST if $STOP_ON_FAIL and not $params{expect_fail};

      warn( "This CRITICAL test has failed - bailing out\n" ), last TEST if $params{critical};
   }
}

{
   our $RUNNING_TEST;

   sub pass
   {
      my ( $testname ) = @_;
      ok( 1, $testname );
   }

   # A convenience for the otherwise-common pattern of
   #   ->on_done( sub { pass $message } )
   sub SyTest::pass_on_done
   {
      my $self = shift;
      my ( $message ) = @_;
      $self->on_done( sub { ok( 1, $message ) } );
   }

   sub ok
   {
      die "Cannot call ok() outside of a multi_test\n" unless $RUNNING_TEST;

      my ( $ok, $stepname ) = @_;
      $RUNNING_TEST->ok( $ok, $stepname );
   }

   sub is_eq
   {
      die "Cannot call is_eq() outside of a multi_test\n" unless $RUNNING_TEST;

      my ( $got, $want, $stepname ) = @_;
      $RUNNING_TEST->ok( my $ok = $got eq $want, $stepname );
      if( !$ok ) {
         $output->diag( "Got $got, expected $want" );
      }
   }

   sub multi_test
   {
      my ( $name, %params ) = @_;

      local $RUNNING_TEST = my $t = $output->enter_multi_test( $name );
      _run_test( $t, %params );
      $t->leave;

      if( $t->failed ) {
         $output->diag( $_ ) for @log_if_fail_lines;
      }
      if( $t->skipped ) {
         $skipped_count++;
      }

      no warnings 'exiting';
      last TEST if $STOP_ON_FAIL and $t->failed and not $params{expect_fail};
   }
}

sub prepare
{
   my ( $name, %params ) = @_;

   local @PROVIDES = @{ $params{provides} || [] };

   my @reqs;
   foreach my $req ( @{ $params{requires} || [] } ) {
      push @reqs, $test_environment{$req} and next if exists $test_environment{$req};

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

   if( not $success ) {
      no warnings 'exiting';
      last TEST if $STOP_ON_FAIL;

      die "prepare failed\n";
   }

   exists $test_environment{$_} or warn "Prepare step $name did not provide a value for $_\n"
      for @PROVIDES;
}

## Some assertion functions useful by test scripts

sub require_json_object
{
   my ( $obj ) = @_;
   ref $obj eq "HASH" or croak "Expected a JSON object";
}

sub require_json_keys
{
   my ( $obj, @keys ) = @_;
   require_json_object( $obj );
   foreach ( @keys ) {
      defined $obj->{$_} or croak "Expected a '$_' key";
   }
}

sub require_json_list
{
   my ( $list ) = @_;
   ref $list eq "ARRAY" or croak "Expected a JSON list";
}

sub require_json_nonempty_list
{
   my ( $list ) = @_;
   require_json_list( $list );
   @$list or croak "Expected a non-empty JSON list";
}

sub require_json_number
{
   my ( $num ) = @_;
   # Our hacked-up JSON decoder represents numbers as JSON::number instances
   ref $num eq "JSON::number" or croak "Expected a JSON number";
}

sub require_json_string
{
   my ( $str ) = @_;
   !ref $str or croak "Expected a JSON string";
}

sub require_json_nonempty_string
{
   my ( $str ) = @_;
   !ref $str and length $str or croak "Expected a non-empty JSON string";
}

use constant JSON_BOOLEAN_CLASS => ref( JSON::true );

sub require_json_boolean
{
   my ( $obj ) = @_;
   ref $obj eq JSON_BOOLEAN_CLASS or croak "Expected a JSON boolean";
}

sub require_base64_unpadded
{
   my ( $str ) = @_;
   !ref $str or croak "Expected a plain string";

   $str =~ m([^A-Za-z0-9+/=]) and
      die "String contains invalid base64 characters";
   $str =~ m(=) and
      die "String contains trailing padding";
}

sub require_base64_unpadded_and_decode
{
   my ( $str ) = @_;
   require_base64_unpadded $str;
   return decode_base64 $str;
}

my %only_files;
my $stop_after;
if( @ARGV ) {
   $only_files{$_}++ for @ARGV;

   $stop_after = maxstr keys %only_files;
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

         $output->run_file( $filename );

         # Slurp and eval() the file instead of do() because then lexical
         # environment such as strict/warnings will still apply
         my $code = do {
            open my $fh, "<", $filename or die "Cannot read $filename - $!\n";
            local $/; <$fh>
         };

         local $SKIPPING = 1 if %only_files and not exists $only_files{$filename};

         # Protect against symbolic leakage between test files by cleaning up
         # extra symbols in the 'main::' namespace
         my %was_symbs = map { $_ => 1 } list_symbols( "main" );

         # Tell eval what the filename is so we get nicer warnings/errors that
         # give the filename instead of (eval 123)
         my $died_during_compile;

         my $success = do {
            local $SIG{__DIE__} = sub {
               return if $^S;
               $died_during_compile = 1 if !defined $^S;
               die @_;
            };

            eval( "#line 1 $filename\n" . $code . "; 1" );
         };

         if( !$success ) {
            die $@ if $died_during_compile;

            chomp( my $e = $@ );
            $output->abort_file( $filename, $e );
            $failed++;
         }

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

if( $WAIT_AT_END ) {
   print STDERR "Waiting... (hit ENTER to end)\n";
   $loop->add( my $stdin = IO::Async::Stream->new_for_stdin( on_read => sub {} ) );
   $stdin->read_until( "\n" )->get;
}

if( $failed ) {
   $output->final_fail( $failed );

   my @f;
   foreach my $synapse ( @{ $test_environment{synapses} } ) {
      $synapse->print_output;
      push @f, $synapse->await_finish;

      $synapse->kill( 'INT' );
   }

   Future->wait_all( @f )->get if @f;
   exit 1;
}
else {
   $output->final_pass( $expected_fail, $skipped_count );
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
