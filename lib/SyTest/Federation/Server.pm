package SyTest::Federation::Server;

use strict;
use warnings;

use base qw( SyTest::Federation::_Base Net::Async::HTTP::Server );

no if $] >= 5.017011, warnings => 'experimental::smartmatch';
use feature qw( switch );

use Carp;

use List::UtilsBy qw( extract_first_by );
use Protocol::Matrix qw( encode_base64_unpadded verify_json_signature );
use HTTP::Headers::Util qw( split_header_words );
use JSON qw( encode_json );

use Struct::Dumb qw( struct );
struct Awaiter => [qw( type matcher f )];

sub _init
{
   my $self = shift;
   my ( $params ) = @_;

   $self->{next_event_id} = 0;

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

sub next_event_id
{
   my $self = shift;
   return sprintf "\$%d:%s", $self->{next_event_id}++, $self->server_name;
}

sub create_event
{
   my $self = shift;
   my %fields = @_;

   defined $fields{$_} or croak "Every event needs a '$_' field"
      for qw( type auth_events content depth prev_events room_id sender );

   if( defined $fields{state_key} ) {
      defined $fields{$_} or croak "Every state event needs a '$_' field"
         for qw( prev_state );
   }

   my $event = {
      %fields,

      event_id         => $self->next_event_id,
      origin           => $self->server_name,
      origin_server_ts => $self->time_ms,
   };

   $self->sign_event( $event );

   return $self->{events_by_id}{ $event->{event_id} } = $event;
}

sub get_event
{
   my $self = shift;
   my ( $id ) = @_;

   my $event = $self->{events_by_id}{$id} or
      croak "$self has no event id '$id'";

   return $event;
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

   my $path = $req->path;
   unless( $path =~ s{^/_matrix/}{} ) {
      $req->respond( HTTP::Response->new( 404, "Not Found", [ Content_Length => 0 ] ) );
      return;
   }

   $self->adopt_future(
      ( # 'key' requests don't need to be signed
         $path =~ m{^key/}
            ? Future->done
            : $self->_check_authorization( $req )
      )->then( sub {
         $self->_dispatch( $path, $req )
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

      $origin eq $body->{origin} or
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
   my ( $path, $req ) = @_;

   my @pc = split m{/}, $path;
   my @trial;
   while( @pc ) {
      push @trial, shift @pc;
      if( my $code = $self->can( "on_request_" . join "_", @trial ) ) {
         return $code->( $self, $req, @pc );
      }
   }

   print STDERR "TODO: Respond to request to /_matrix/${\join '/', @trial}\n";

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

   my $fedparams = $self->{federation_params};

   Future->done( json => $self->signed_data( {
      server_name => $fedparams->server_name,
      tls_fingerprints => [
         { $algo => encode_base64_unpadded( $fingerprint ) },
      ],
      valid_until_ts => ( time + 86400 ) * 1000, # +24h in msec
      verify_keys => {
         $fedparams->key_id => {
            key => encode_base64_unpadded( $fedparams->public_key ),
         },
      },
      old_verify_keys => {},
   } ) );
}

sub mk_await_request_pair
{
   my $class = shift;
   my ( $shortname, $paramnames ) = @_;
   my @paramnames = @$paramnames;

   my $okey = "awaiting_$shortname";

   my $awaitfunc = sub {
      my $self = shift;
      my @paramvalues = splice @_, 0, scalar @paramnames;

      my $ikey = join "\0", @paramvalues;

      croak "Cannot await another $shortname to @paramvalues"
         if $self->{$okey}{$ikey};

      return $self->{$okey}{$ikey} = Future->new
         ->on_cancel( sub {
            print STDERR "Cancelling unused $shortname await for @paramvalues";
            delete $self->{$okey}{$ikey};
         });
   };

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
      else {
         Future->done( response => HTTP::Response->new(
            404, "Not found", [ Content_length => 0 ], "",
         ) );
      }
   };

   no strict 'refs';
   *{"${class}::await_$shortname"} = $awaitfunc;
   *{"${class}::on_request_federation_v1_$shortname"} = $on_requestfunc;
}

__PACKAGE__->mk_await_request_pair(
   query_directory => [qw( ?room_alias )],
);

__PACKAGE__->mk_await_request_pair(
   query_profile => [qw( ?user_id )],
);

__PACKAGE__->mk_await_request_pair(
   make_join => [qw( :room_id :user_id )],
);

__PACKAGE__->mk_await_request_pair(
   send_join => [qw( :room_id )],
);

sub on_request_federation_v1_send
{
   my $self = shift;
   my ( $req, $tid ) = @_;

   my $body = $req->body_from_json;

   my $origin = $body->{origin};

   foreach my $edu ( @{ $body->{edus} } ) {
      next if $self->on_edu( $edu, $origin );

      print STDERR "TODO: Unhandled incoming EDU of type '$edu->{edu_type}'\n";
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

1;
