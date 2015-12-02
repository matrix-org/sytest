use Future::Utils qw( repeat );

push our @EXPORT, qw( AS_USER await_as_event );

our $AS_USER = fixture(
   requires => [ $main::API_CLIENTS[0], $main::AS_USER_INFO ],

   setup => sub {
      my ( $http, $as_user_info ) = @_;

      Future->done( User( $http, $as_user_info->user_id, $as_user_info->as2hs_token,
            undef, undef, [], undef ) );
   },
);

# Map event types to ARRAYs of Futures
my %futures_by_type;

sub await_as_event
{
   my ( $type ) = @_;
   my $failmsg = SyTest::CarpByFile::shortmess(
      "Timed out waiting for an AS event of type $type"
   );

   push @{ $futures_by_type{$type} }, my $f = $loop->new_future;

   return Future->wait_any(
      $f,

      delay( 10 )
         ->then_fail( $failmsg ),
   );
}

my $f = repeat {
   await_http_request( qr{^/appserv/transactions/\d+$}, sub { 1 },
      timeout => 0,
   )->then( sub {
      my ( $request ) = @_;

      # Respond immediately to AS
      $request->respond_json( {} );

      foreach my $event ( @{ $request->body_from_json->{events} } ) {
         my $type = $event->{type};

         my $queue = $futures_by_type{$type};

         # Ignore any cancelled ones
         shift @$queue while $queue and @$queue and $queue->[0]->is_cancelled;

         if( $queue and my $f = shift @$queue ) {
            $f->done( $event, $request );
         }
         else {
            print "Ignoring incoming AS event of type $type\n";
         }
      }

      Future->done;
   })
} while => sub { not $_[0]->failure };

$f->on_fail( sub { die $_[0] } );

# lifecycle it
$f->on_cancel( sub { undef $f } );
