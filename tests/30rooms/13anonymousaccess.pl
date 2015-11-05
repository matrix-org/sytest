test "Anonymous user cannot view non-world-readable rooms",
   requires => [ qw( first_api_client ), local_user_preparer() ],

   do => sub {
      my ( $api_client, $user ) = @_;

      my $anonymous_user;
      my $room_id;

      register_anonymous_user( $api_client )->then( sub {
         ( $anonymous_user ) = @_;

         matrix_create_and_join_room( [ $user ] )
         ->then( sub {
            ( $room_id ) = @_;

            matrix_put_room_state( $user, $room_id,
               type    => "m.room.history_visibility",
               content => { history_visibility => "shared" }
            );
         })->then( sub {
            matrix_send_room_text_message( $user, $room_id, body => "mice" )
         })->then( sub {
            do_request_json_for( $anonymous_user,
               method => "GET",
               uri    => "/api/v1/rooms/$room_id/messages",
               params => {
                  limit => "1",
                  dir   => "b",
               },
            )
         })->main::expect_http_403;
      });
   };

test "Anonymous user can view world-readable rooms",
   requires => [ qw( first_api_client ), local_user_preparer() ],

   do => sub {
      my ( $api_client, $user ) = @_;

      my $anonymous_user;
      my $room_id;

      register_anonymous_user( $api_client )->then( sub {
         ( $anonymous_user ) = @_;

         matrix_create_and_join_room( [ $user ] )
         ->then( sub {
            ( $room_id ) = @_;

            matrix_put_room_state( $user, $room_id,
               type    => "m.room.history_visibility",
               content => { history_visibility => "world_readable" }
            );
         })->then( sub {
            matrix_send_room_text_message( $user, $room_id, body => "mice" )
         })->then( sub {
            do_request_json_for( $anonymous_user,
               method => "GET",
               uri    => "/api/v1/rooms/$room_id/messages",
               params => {
                  limit => "2",
                  dir   => "b",
               },
            )
         });
      });
   };

sub register_anonymous_user
{
   my ( $http ) = @_;

   $http->do_request_json(
      method  => "POST",
      uri     => "/v2_alpha/register",
      content => {},
      params  => {
         kind => "guest",
      },
   )->then( sub {
      my ( $body ) = @_;
      my $access_token = $body->{access_token};

      Future->done( User( $http, $body->{user_id}, $access_token, undef, undef, [], undef ) );
   });
}
