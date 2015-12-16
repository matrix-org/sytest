package SyTest::Federation::Client;

use strict;
use warnings;

use base qw( SyTest::Federation::_Base SyTest::HTTPClient );

use MIME::Base64 qw( decode_base64 );
use HTTP::Headers::Util qw( join_header_words );

sub _fetch_key
{
   my $self = shift;
   my ( $server_name, $key_id ) = @_;

   $self->do_request_json(
      method   => "GET",
      hostname => $server_name,
      full_uri => "/_matrix/key/v2/server/$key_id",
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

sub send_edu
{
   my $self = shift;
   my %params = @_;

   my $ts = $self->time_ms;

   my %transaction = (
      origin           => $self->server_name,
      origin_server_ts => JSON::number( $ts ),
      previous_ids     => [], # TODO
      pdus             => [],
      edus             => [
         {
            edu_type => $params{edu_type},
            content  => $params{content},
            origin   => $self->server_name,
            destination => $params{destination},
         }
      ],
   );

   $self->do_request_json(
      method   => "PUT",
      hostname => $params{destination},
      uri      => "/send/$ts/",

      content => \%transaction,
   )->then_done(); # response body is empty
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
      uri      => "/make_join/$room_id/$user_id"
   )->then( sub {
      my ( $body ) = @_;

      my $protoevent = $body->{event};

      my %member_event = (
         ( map { $_ => $protoevent->{$_} } qw(
            auth_events content depth prev_events prev_state room_id sender
            state_key type ) ),

         event_id         => $store->next_event_id,
         origin           => $store->server_name,
         origin_server_ts => $self->time_ms,
      );

      # TODO: really ought to sign it...

      $self->do_request_json(
         method   => "PUT",
         hostname => $server_name,
         uri      => "/send_join/$room_id/$member_event{event_id}",

         content => \%member_event,
      )->then( sub {
         my ( $join_body ) = @_;
         # SYN-490 workaround
         $join_body = $join_body->[1] if ref $join_body eq "ARRAY";

         my $room = SyTest::Federation::Room->new(
            datastore => $store,
            room_id   => $room_id,
         );

         my %done_event;
         foreach my $event ( @{ $join_body->{auth_chain} }, @{ $join_body->{state} } ) {
            $done_event{ $event->{event_id} }++ or
               $room->insert_event( $event );
         }

         $room->insert_event( \%member_event );

         Future->done( $room );
      });
   });
}

1;
