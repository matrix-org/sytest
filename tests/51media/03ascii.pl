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

# we only need one user for these tests
my $user_fixture = local_user_fixture();

sub assert_cd_params_match_filename {
   my ( $filename, $cd_params ) = @_;

   # either we need a valid "filename*" param
   if ( $cd_params->{"filename*"} ) {
      my $f = $cd_params->{"filename*"};
      $f =~ s/%(..)/chr hex $1/eg;
      assert_eq( $f, "utf-8''$filename", "filename*" );

      # there might also be a 'filename', but it doesn't really matter what it
      # is.
      return;
   }

   # or we need a valid filename
   my $f = $cd_params->{"filename"};
   assert_eq( $f, $filename, "filename" );
}

foreach my $filename ( "ascii", "name with spaces", "name;with;semicolons" ) {
   test "Can download file '$filename'",
      requires => [
         $user_fixture, $main::API_CLIENTS[1]
      ],

      check => sub {
         my ( $user, $federation_client ) = @_;

         my $content_id;

         # first upload the content with the given filename
         upload_test_content( $user, filename=>$filename )->then( sub {
            ( $content_id ) = @_;

            # try and fetch it as a local user
            get_media( $user->http, $content_id );
         })->then( sub {
            assert_cd_params_match_filename( $filename, $_[0] );

            # do the same over federation
            get_media( $federation_client, $content_id );
         })->then( sub {
            assert_cd_params_match_filename( $filename, $_[0] );
            Future->done(1);
         });
      };
}


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
      matrix_send_room_message( $user, $room_id,
         content => { msgtype => "m.file", body => "test.txt", url => $content_uri }
      );
   };

test "Can fetch images in room",
   requires => [ $main::API_CLIENTS[0], local_user_and_room_fixtures() ],

   check => sub {
      my ( $http, $user, $room_id ) = @_;
      matrix_send_room_message_synced( $user, $room_id,
         content => { msgtype => "m.text", body => "test" }
      )->then( sub {
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
