test "Can logout current device",
   requires => [ local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user ) = @_;

      my $other_login;

      matrix_login_again_with_user( $user )
      ->then( sub {
         ( $other_login ) = @_;

         do_request_json_for( $user,
            method => "POST",
            uri    => "/r0/logout",
            content => {},
         )
      })->then( sub {
         # our access token should be invalidated
         repeat_until_true {
            matrix_sync( $user )->main::check_http_code(
               401 => "ok",
               200 => "redo",
            );
         };
      })->then( sub {
         matrix_sync( $other_login );
      });
   };


test "Can logout all devices",
   requires => [ local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user ) = @_;

      my $other_login;

      matrix_login_again_with_user( $user )
      ->then( sub {
         ( $other_login ) = @_;

         do_request_json_for( $user,
            method => "POST",
            uri    => "/r0/logout/all",
            content => {},
         )
      })->then( sub {
         # our access token should be invalidated
         repeat_until_true {
            matrix_sync( $user )->main::check_http_code(
               401 => "ok",
               200 => "redo",
            );
         };
      })->then( sub {
         # our access token should be invalidated
         repeat_until_true {
            matrix_sync( $other_login )->main::check_http_code(
               401 => "ok",
               200 => "redo",
            );
         };
      });
   };
