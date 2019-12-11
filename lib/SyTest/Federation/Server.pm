package SyTest::Federation::Server;

use strict;
use warnings;
use 5.014;  # So we can use the /r flag to s///

use base qw( SyTest::Federation::_Base Net::Async::HTTP::Server
   SyTest::Federation::AuthChecks
);

no if $] >= 5.017011, warnings => 'experimental::smartmatch';
use feature qw( switch );

use Carp;

use List::UtilsBy qw( extract_first_by );
use Protocol::Matrix qw( encode_base64_unpadded verify_json_signature );
use HTTP::Headers::Util qw( split_header_words );
use JSON qw( encode_json );

use Struct::Dumb qw( struct );
struct Awaiter => [qw( type matcher f )];
struct RoomAwaiter => [qw( type room_id matcher f )];

sub _init
{
   my $self = shift;
   my ( $params ) = @_;

   # Use 'on_request' as a configured parameter rather than a subclass method
   # so that the '$CLIENT_LOG' logic in run-tests.pl can properly put
   # debug-printing wrapping logic around it.
   $params->{on_request} = \&on_request;

   return $self->SUPER::_init( @_ );
}

sub configure
{
   my $self = shift;
   my %params = @_;

   foreach (qw( client )) {
      $self->{$_} = delete $params{$_} if exists $params{$_};
   }

   return $self->SUPER::configure( %params );
}

sub client
{
   my $self = shift;
   return $self->{client};
}

sub _fetch_key
{
   my $self = shift;
   return $self->{client}->_fetch_key( @_ );
}

sub make_request
{
   my $self = shift;
   return SyTest::HTTPServer::Request->new( @_ );
}

sub on_request
{
   my $self = shift;
   my ( $req ) = @_;

   my $uri = $req->as_http_request->uri;
   my @pc = $uri->path_segments;

   # Remove the initial empty component as it ought to be an absolute request
   shift @pc if $pc[0] eq "";

   unless( $pc[0] eq "_matrix" ) {
      $req->respond( HTTP::Response->new( 404, "Not Found", [ Content_Length => 0 ] ) );
      return;
   }
   shift @pc;

   $self->adopt_future(
      ( # 'key' requests don't need to be signed
         $pc[0] eq "key"
            ? Future->done
            : $self->_check_authorization( $req )
      )->then( sub {
         $self->_dispatch( $req, @pc )
      })->else_with_f( sub {
         my ( $f, undef, $name ) = @_;
         return $f unless $name and $name eq "matrix_auth";

         # Turn 'matrix_auth' failures into HTTP responses
         my ( undef, $message ) = @_;
         my $body = encode_json {
            errcode => "M_UNAUTHORIZED",
            error   => $message,
         };

         Future->done( response => HTTP::Response->new(
            403, undef, [
               Content_Length => length $body,
               Content_Type   => "application/json",
            ], $body
         ) );
      })->on_done( sub {
         return unless @_;

         for ( shift ) {
            when( "response" ) {
               my ( $response ) = @_;
               $req->respond( $response );
            }
            when( "json" ) {
               my ( $data ) = @_;
               $req->respond_json( $data );
            }
            default {
               croak "Unsure how to handle response type $_";
            }
         }
      })
   );
}

sub _check_authorization
{
   my $self = shift;
   my ( $req ) = @_;

   my $auth = $req->header( "Authorization" ) // "";

   $auth =~ s/^X-Matrix\s+// or
      return Future->fail( "No Authorization of scheme X-Matrix", matrix_auth => );

   # split_header_words gives us a list of two-element ARRAYrefs
   my %auth_params = map { @$_ } split_header_words( $auth );

   defined $auth_params{$_} or
      return Future->fail( "Missing '$_' parameter to X-Matrix Authorization", matrix_auth => ) for qw( origin key sig );

   my $origin = $auth_params{origin};

   my %to_verify = (
      method      => $req->method,
      uri         => $req->as_http_request->uri->path_query,
      origin      => $origin,
      destination => $self->server_name,
      signatures  => {
         $origin => {
            $auth_params{key} => $auth_params{sig},
         },
      },
   );

   if( length $req->body ) {
      my $body = $req->body_from_json;

      !exists $body->{origin} or $origin eq $body->{origin} or
         return Future->fail( "'origin' in Authorization header does not match content", matrix_auth => );

      $to_verify{content} = $body;
   }

   $self->get_key(
      server_name => $origin,
      key_id      => $auth_params{key},
   )->then( sub {
      my ( $public_key ) = @_;

      eval { verify_json_signature( \%to_verify,
         public_key => $public_key,
         origin     => $auth_params{origin},
         key_id     => $auth_params{key}
      ) } and return Future->done;

      chomp ( my $message = $@ );
      return Future->fail( $message, matrix_auth => );
   });
}

sub _dispatch
{
   my $self = shift;
   my ( $req, @pc ) = @_;

   my @trial;
   while( @pc ) {
      push @trial, shift @pc;
      if( my $code = $self->can( "on_request_" . join "_", @trial ) ) {
         return $code->( $self, $req, @pc );
      }
   }

   warn "TODO: Respond to request to /_matrix/${\join '/', @trial}";

   return Future->done(
      response => HTTP::Response->new(
         404, "Not Found",
         [ Content_Length => 0 ],
      )
   );
}

sub on_request_key_v2_server
{
   my $self = shift;
   my ( $req, $keyid ) = @_;

   my $sock = $req->stream->read_handle;
   my $ssl = $sock->_get_ssl_object;  # gut-wrench into IO::Socket::SSL - see RT105733
   my $cert = Net::SSLeay::get_certificate( $ssl );

   my $algo = "sha256";
   my $fingerprint = Net::SSLeay::X509_digest( $cert, Net::SSLeay::EVP_get_digestbyname( $algo ) );

   Future->done( json => $self->signed_data( {
      server_name => $self->server_name,
      tls_fingerprints => [
         { $algo => encode_base64_unpadded( $fingerprint ) },
      ],
      valid_until_ts => ( time + 86400 ) * 1000, # +24h in msec
      verify_keys => {
         $self->key_id => {
            key => encode_base64_unpadded( $self->{datastore}->public_key ),
         },
      },
      old_verify_keys => {},
   } ) );
}

sub on_request_federation_v1_query_directory
{
   my $self = shift;
   my ( $req, $alias ) = @_;

   my $room_id = $self->{datastore}->lookup_alias( $alias ) or
      return Future->done( response => HTTP::Response->new(
         404, "Not found", [ Content_length => 0 ], "",
      ) );

   Future->done( json => {
      room_id => $room_id,
      servers => [ $self->server_name ],
   } );
}

sub on_request_federation_v1_event
{
   my $self = shift;
   my ( $req, $event_id ) = @_;

   my $event = $self->{datastore}->get_event( $event_id ) or
      return Future->done( response => HTTP::Response->new(
         404, "Not found", [ Content_length => 0 ], "",
      ) );

   Future->done( json => {
      origin           => $self->server_name,
      origin_server_ts => JSON::number( $self->time_ms ),
      pdus             => [
         $event,
      ]
   } );
}

sub on_request_federation_v1_make_join
{
   my $self = shift;
   my ( $req, $room_id, $user_id ) = @_;

   my $room = $self->{datastore}->get_room( $room_id ) or
      return Future->done( response => HTTP::Response->new(
         404, "Not found", [ Content_length => 0 ], "",
      ) );

   Future->done( json => {
      event => $room->make_join_protoevent(
         user_id => $user_id,
      ),
   } );
}

sub on_request_federation_v1_send_join
{
   my $self = shift;

   $self->on_request_federation_v2_send_join( @_ )->then( sub {
      my $res = @_;

      # /v1/send_join has an extraneous [ 200, ... ] wrapper (see MSC1802)
      Future->done( json => [ 200, $res ] );
   })
}

sub on_request_federation_v2_send_join
{
   my $self = shift;
   my ( $req, $room_id ) = @_;

   my $store = $self->{datastore};

   my $room = $store->get_room( $room_id ) or
      return Future->done( response => HTTP::Response->new(
         404, "Not found", [ Content_length => 0 ], "",
      ) );

   my $event = $req->body_from_json;

   my @auth_chain = $store->get_auth_chain_events(
      map { $_->[0] } @{ $event->{auth_events} }
   );
   my @state_events = $room->current_state_events;

   $room->insert_event( $event );

   Future->done( json => {
      auth_chain => \@auth_chain,
      state      => \@state_events,
   } );
}

sub mk_await_request_pair
{
   my $class = shift;
   my ( $versionprefix, $shortname, $paramnames ) = @_;
   my @paramnames = @$paramnames;

   my $okey = "awaiting_${versionprefix}_${shortname}";

   my $awaitfunc = sub {
      my $self = shift;
      my @paramvalues = splice @_, 0, scalar @paramnames;

      my $ikey = join "\0", @paramvalues;

      croak "Cannot await another $shortname to @paramvalues"
         if $self->{$okey}{$ikey};

      return $self->{$okey}{$ikey} = Future->new
         ->on_cancel( sub {
            warn "Cancelling unused $shortname await for @paramvalues";
            delete $self->{$okey}{$ikey};
         });
   };

   my $was_on_requestfunc = $class->can(
      "on_request_federation_${versionprefix}_${shortname}"
   );
   my $on_requestfunc = sub {
      my $self = shift;
      my ( $req, @pathvalues ) = @_;

      my @paramvalues;
      # :name is the next path component, ?name is a request param
      foreach my $name ( @paramnames ) {
         if( $name =~ m/^:/ ) {
            push @paramvalues, shift @pathvalues;
            next;
         }

         if( $name =~ m/^\?(.*)$/ ) {
            push @paramvalues, $req->query_param( $1 );
            next;
         }

         die "Unsure what to do with paramname $name\n";
      }

      my $ikey = join "\0", @paramvalues;

      if( my $f = delete $self->{$okey}{$ikey} ) {
         $f->done( $req, @paramvalues );
         Future->done;
      }
      elsif( $was_on_requestfunc ) {
         return $self->$was_on_requestfunc( $req, @paramvalues );
      }
      else {
         Future->done( response => HTTP::Response->new(
            404, "Not found", [ Content_length => 0 ], "",
         ) );
      }
   };

   no strict 'refs';
   no warnings 'redefine';
   *{"${class}::await_request_${versionprefix}_${shortname}"} = $awaitfunc;
   # Deprecated alternative name for v1 endpoints.
   *{"${class}::await_request_${shortname}"} = $awaitfunc if ${versionprefix} eq "v1";
   *{"${class}::on_request_federation_${versionprefix}_${shortname}"} = $on_requestfunc;
}

__PACKAGE__->mk_await_request_pair(
   "v1", "query_directory", [qw( ?room_alias )],
);

__PACKAGE__->mk_await_request_pair(
   "v1", "query_profile", [qw( ?user_id )],
);

__PACKAGE__->mk_await_request_pair(
   "v1", "make_join", [qw( :room_id :user_id )],
);

__PACKAGE__->mk_await_request_pair(
   "v1", "make_leave", [qw( :room_id :user_id )],
);

__PACKAGE__->mk_await_request_pair(
   "v1", "send_join", [qw( :room_id )],
);

__PACKAGE__->mk_await_request_pair(
   "v2", "send_join", [qw( :room_id )],
);

__PACKAGE__->mk_await_request_pair(
   "v1", "state_ids", [qw( :room_id ?event_id )],
);

__PACKAGE__->mk_await_request_pair(
   "v1", "state", [qw( :room_id )],
);

__PACKAGE__->mk_await_request_pair(
   "v1", "get_missing_events", [qw( :room_id )],
);

__PACKAGE__->mk_await_request_pair(
   "v1", "event_auth", [qw( :room_id :event_id )],
);

__PACKAGE__->mk_await_request_pair(
   "v1", "backfill", [qw( :room_id )],
);

__PACKAGE__->mk_await_request_pair(
   "v1", "invite", [qw( :room_id )],
);

__PACKAGE__->mk_await_request_pair(
   "v2", "invite", [qw( :room_id )],
);

__PACKAGE__->mk_await_request_pair(
   "v1", "event", [qw( :event_id )],
);

__PACKAGE__->mk_await_request_pair(
   "v1", "user_devices", [qw( :user_id )],
);

__PACKAGE__->mk_await_request_pair(
   "v1", "user_keys_query", [qw( )],
);

sub on_request_federation_v1_send
{
   my $self = shift;
   my ( $req, $tid ) = @_;

   my $body = $req->body_from_json;

   my $origin = $body->{origin};

   foreach my $edu ( @{ $body->{edus} } ) {
      my $type = $edu->{edu_type};

      next if $self->on_edu( $edu, $origin );

      my $code = $self->can( "on_edu_" . ( $type =~ s/\./_/gr ) );
      next if $code and $self->$code( $edu, $origin );

      warn "TODO: Unhandled incoming EDU of type '$type'";
   }

   # A PDU is an event
   foreach my $event ( @{ $body->{pdus} } ) {
      next if $self->on_event( $event );

      warn "TODO: Unhandled incoming event of type '$event->{type}'";
   }

   Future->done( json => {} );
}

sub await_edu
{
   my $self = shift;
   my ( $edu_type, $matcher ) = @_;

   push @{ $self->{edu_waiters} }, Awaiter( $edu_type, $matcher, my $f = $self->loop->new_future );

   return $f;
}

sub on_edu
{
   my $self = shift;
   my ( $edu, $origin ) = @_;

   my $edu_type = $edu->{edu_type};

   my $awaiter = extract_first_by {
      $_->type eq $edu_type and ( not $_->matcher or $_->matcher->( $edu, $origin ) )
   } @{ $self->{edu_waiters} //= [] } or
      return;

   $awaiter->f->done( $edu, $origin );
   return 1;
}

sub on_edu_m_presence
{
   # silently ignore
   return 1;
}

sub await_event
{
   my $self = shift;
   my ( $type, $room_id, $matcher ) = @_;

   push @{ $self->{event_waiters} }, RoomAwaiter( $type, $room_id, $matcher, my $f = $self->loop->new_future );

   return $f;
}

sub on_event
{
   my $self = shift;
   my ( $event ) = @_;

   my $type    = $event->{type};
   my $room_id = $event->{room_id};

   my $awaiter = extract_first_by {
      $_->type eq $type and $_->room_id eq $room_id and
         ( not $_->matcher or $_->matcher->( $event ) )
   } @{ $self->{event_waiters} //= [] } or
      return;

   $awaiter->f->done( $event );
   return 1;
}

1;
