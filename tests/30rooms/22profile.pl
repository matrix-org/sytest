test "displayname updates affect room member events",
   requires => [ local_user_and_room_fixtures() ],

   do => sub {
      my ( $user, $room_id ) = @_;

      my $uri = "/r0/profile/:user_id/displayname";

      do_request_json_for($user,
         method => "GET",
         uri    => $uri,
      )->then( sub {
         my ( $body ) = @_;

         # N.B. nowadays we let servers specify default displayname & avatar_url
         # previously we asserted that these must be undefined at this point.

         do_request_json_for( $user,
            method  => "PUT",
            uri     => $uri,
            content => {
               displayname => "LemurLover",
            },
         )
      })->then( sub {
         do_request_json_for( $user,
            method => "GET",
            uri    => "/r0/rooms/$room_id/state/m.room.member/:user_id",
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_eq( $body->{displayname}, "LemurLover", "Room displayname" );

         Future->done( 1 );
      });
   };

test "avatar_url updates affect room member events",
   requires => [ local_user_and_room_fixtures() ],

   do => sub {
      my ( $user, $room_id ) = @_;

      my $uri = "/r0/profile/:user_id/avatar_url";
      my $avatar_url;

      upload_test_image(
         $user
      )->then( sub {
         my ( $content_uri, ) = @_;

         $avatar_url = $content_uri->as_string;

         do_request_json_for($user,
            method => "GET",
            uri    => $uri,
         );
      })->then( sub {
         my ( $body ) = @_;

         # N.B. nowadays we let servers specify default displayname & avatar_url
         # previously we asserted that these must be undefined at this point.

         do_request_json_for( $user,
            method  => "PUT",
            uri     => $uri,
            content => {
               avatar_url => $avatar_url,
            },
         )
      })->then( sub {
         do_request_json_for( $user,
            method => "GET",
            uri    => "/r0/rooms/$room_id/state/m.room.member/:user_id",
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_eq( $body->{avatar_url}, $avatar_url, "Room avatar_url" );

         Future->done( 1 );
      });
   };

test "Changing avatar to non-image media is disallowed",
   requires => [ local_user_fixture() ],
   do => sub {
      my ( $user, ) = @_;
      my $content_id;

      upload_test_content(
         $user, filename=>"ascii"
      )->then( sub {
         ( $content_id ) = @_;

         log_if_fail "New avatar url", $content_id;

         my $user_id= $user->user_id;
         do_request_json_for(
            $user,
            method => "PUT",
            uri    => "/r0/profile/$user_id/avatar_url",
            params => {
               user_id => $user_id,
            },
            content => { avatar_url => $content_id },
         );
      })->main::expect_http_4xx;
   }
