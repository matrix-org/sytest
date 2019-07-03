package SyTest::Federation::Client;

use strict;
use warnings;

use base qw( SyTest::Federation::_Base SyTest::HTTPClient );

use List::UtilsBy qw( uniq_by );

use MIME::Base64 qw( decode_base64 );
use HTTP::Headers::Util qw( join_header_words );

use SyTest::Assertions qw( :all );

use URI::Escape qw( uri_escape );

sub configure
{
   my $self = shift;
   my %params = @_;

   # there may be multiple concurrent requests; for example, while processing a
   # /send request, synapse may send us back a /get_missing_events/ request, which
   # we have to authenticate, so make a /keys request.
   $params{max_connections_per_host} //= 0;

   return $self->SUPER::configure( %params );
}

sub _fetch_key
{
   my $self = shift;
   my ( $server_name, $key_id ) = @_;

   my $key_id_encoded = uri_escape($key_id);

   $self->do_request_json(
      method   => "GET",
      hostname => $server_name,
      full_uri => "/_matrix/key/v2/server/$key_id_encoded",
   )->then( sub {
      my ( $body ) = @_;

      defined $body->{server_name} and $body->{server_name} eq $server_name or
         return Future->fail( "Response 'server_name' does not match", matrix => );

      $body->{verify_keys} and $body->{verify_keys}{$key_id} and my $key = $body->{verify_keys}{$key_id}{key} or
         return Future->fail( "Response did not provide key '$key_id'", matrix => );

      $key = decode_base64( $key );

      # TODO: Check the self-signedness of the key response

      Future->done( $key );
   });
}

sub do_request_json
{
   my $self = shift;
   my %params = @_;

   my $uri = $self->full_uri_for( %params );
   if( !$uri->scheme ) {
      defined $params{hostname} or die "Need a 'hostname'";
      $uri = URI->new( "https://$params{hostname}" . $uri );

      delete $params{uri};
      $params{full_uri} = $uri;
   }

   my $origin = $self->server_name;
   my $key_id = $self->key_id;

   my %signing_block = (
      method => $params{method},
      uri    => $uri->path_query,  ## TODO: Matrix spec is unclear on this bit
      origin => $origin,
      destination => $uri->authority,
   );

   if( defined $params{content} ) {
      $signing_block{content} = $params{content};
   }

   $self->sign_data( \%signing_block );

   my $signature = $signing_block{signatures}{$origin}{$key_id};

   my $auth = "X-Matrix " . join_header_words(
      [ origin => $origin ],
      [ key    => $key_id ],
      [ sig    => $signature ],
   );

   # TODO: SYN-437 synapse does not like OWS between auth-param elements
   $auth =~ s/, +/,/g;

   $self->SUPER::do_request_json(
      %params,
      headers => [
         @{ $params{headers} || [] },
         Authorization => $auth,
      ],
   );
}

sub send_transaction
{
   my $self = shift;
   my %params = @_;

   my $ts = $self->time_ms;

   my %transaction = (
      origin           => $self->server_name,
      origin_server_ts => JSON::number( $ts ),
      previous_ids     => [], # TODO
      pdus             => $params{pdus} // [],
      edus             => $params{edus} // [],
   );

   $self->do_request_json(
      method   => "PUT",
      hostname => $params{destination},
      uri      => "/v1/send/$ts/",

      content => \%transaction,
   );
}

sub send_edu
{
   my $self = shift;
   my %params = @_;

   $self->send_transaction(
      %params,
      edus => [
         {
            edu_type => $params{edu_type},
            content  => $params{content},
            origin   => $self->server_name,
            destination => $params{destination},
         }
      ],
   )->then_done(); # TODO: check response
}

sub send_event
{
   my $self = shift;
   my %params = @_;

   my $event = delete $params{event};

   $self->send_transaction(
      %params,
      pdus => [ $event ],
   )->then( sub {
      my ( $body ) = @_;
      assert_deeply_eq( $body,
                        { pdus => { $event->{event_id} => {} } },
                        "/send/ response" );
      Future->done;
   });
}

sub join_room
{
   my $self = shift;
   my %args = @_;

   my $server_name = $args{server_name};
   my $room_id     = $args{room_id};
   my $user_id     = $args{user_id};

   my $store = $self->{datastore};

   $self->do_request_json(
      method   => "GET",
      hostname => $server_name,
      uri      => "/v1/make_join/$room_id/$user_id"
   )->then( sub {
      my ( $body ) = @_;

      my $protoevent = $body->{event};

      my %member_event = (
         ( map { $_ => $protoevent->{$_} } qw(
            auth_events content depth prev_events room_id sender
            state_key type ) ),

         event_id         => $store->next_event_id,
         origin           => $store->server_name,
         origin_server_ts => $self->time_ms,
      );

      $store->sign_event( \%member_event );

      $self->do_request_json(
         method   => "PUT",
         hostname => $server_name,
         uri      => "/v1/send_join/$room_id/$member_event{event_id}",

         content => \%member_event,
      )->then( sub {
         my ( $join_body ) = @_;
         # SYN-490 workaround
         $join_body = $join_body->[1] if ref $join_body eq "ARRAY";

         my $room = SyTest::Federation::Room->new(
            datastore => $store,
            room_id   => $room_id,
         );

         my @events = uniq_by { $_->{event_id} } (
            @{ $join_body->{auth_chain} },
            @{ $join_body->{state} },
            \%member_event,
         );

         $room->insert_event( $_ ) for @events;

         Future->done( $room );
      });
   });
}

=head2 get_remote_forward_extremities

   $client->get_remote_forward_extremities(
      server_name => $first_home_server,
      room_id     => $room_id,
   )->then( sub {
      my ( @extremity_event_ids ) = @_;
   });

Returns the remote server's idea of the current forward extremities in the
given room.

=cut


sub get_remote_forward_extremities
{
   my $self = shift;
   my %args = @_;

   my $server_name = $args{server_name};
   my $room_id     = $args{room_id};

   # we do this slightly hackily, by asking the server to make us a join event,
   # which will handily list the forward extremities as prev_events.

   my $user_id = '@fakeuser:' . $self->server_name;
   $self->do_request_json(
      method   => "GET",
      hostname => $server_name,
      uri      => "/v1/make_join/$room_id/$user_id",
   )->then( sub {
      my ( $resp ) = @_;

      my $protoevent = $resp->{event};

      my @prev_events = map { $_->[0] } @{ $protoevent->{prev_events} };
      Future->done( @prev_events );
   });
}

1;
