my $content_id;
my $content_uri;

test "Can upload with ASCII file name",
   requires => [ local_user_fixture() ],

   do => sub {
      my ( $user ) = @_;
      upload_test_content( $user, filename=>"ascii" )->then( sub {
         ( $content_id, $content_uri ) = @_;
         Future->done(1);
      });
   };

# These next two tests do the same thing with two different HTTP clients, to
# test locally and via federation

sub test_using_client
{
   my ( $client ) = @_;

   get_media( $client, $content_id )->then( sub {
      my ( $disposition ) = @_;

      $disposition eq "inline; filename=ascii" or
         die "Expected an ASCII filename parameter";

      Future->done(1);
   });
}

test "Can download with ASCII file name locally",
   requires => [ $main::API_CLIENTS[0] ],

   check => sub {
      my ( $http ) = @_;
      test_using_client( $http )
      ->then( sub {
         test_using_client( $http )
      });
   };

test "Can download with ASCII file name over federation",
   requires => [ $main::API_CLIENTS[1] ],

   check => sub {
      my ( $http ) = @_;
      test_using_client( $http )
      ->then( sub {
         test_using_client( $http )
      });
   };

test "Can download specifying a different ASCII file name",
   requires => [ $main::API_CLIENTS[0] ],

   check => sub {
      my ( $http ) = @_;

      $http->do_request(
         method   => "GET",
         full_uri => "/_matrix/media/r0/download/$content_id/also_ascii",
      )->then( sub {
         my ( $body, $response ) = @_;

         my $disposition = $response->header( "Content-Disposition" );
         $disposition eq "inline; filename=also_ascii" or
            die "Expected an ASCII filename parameter";

         Future->done(1);
      });
   };

test "Can send image in room message",
   requires => [ $main::API_CLIENTS[0], local_user_and_room_fixtures() ],

   check => sub {
      my ( $http, $user, $room_id ) = @_;
      test_using_client( $http )
      ->then( sub {
         matrix_send_room_message( $user, $room_id,
            content => { msgtype => "m.file", body => "test.txt", url => $content_uri }
         )
      });
   };

test "Can fetch images in room",
   requires => [ $main::API_CLIENTS[0], local_user_and_room_fixtures() ],

   check => sub {
      my ( $http, $user, $room_id ) = @_;
      test_using_client( $http )
      ->then( sub {
         matrix_send_room_message_synced( $user, $room_id,
            content => { msgtype => "m.text", body => "test" }
         )
      })->then( sub {
         matrix_send_room_message_synced( $user, $room_id,
            content => { msgtype => "m.file", body => "test.txt", url => $content_uri }
         )
      })->then( sub {
         do_request_json_for( $user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/messages",
            params => {
               filter => '{"contains_url":true}',
               dir    => 'b',
            }
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( start end chunk ));

         assert_eq( scalar @{ $body->{chunk} }, 1, "Expected 1 message" );

         Future->done( 1 );
      });
   };
