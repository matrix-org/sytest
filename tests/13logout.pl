use Future::Utils qw( try_repeat_until_success );

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
         my $delay = 0.1;
         # our access token should be invalidated
         try_repeat_until_success {
            matrix_sync( $user )->main::expect_http_401
            ->else_with_f( sub {
               my ( $f ) = @_; delay( $delay *= 1.5 )->then( sub { $f } );
            })
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
         my $delay = 0.1;
         # our access token should be invalidated
         try_repeat_until_success {
            matrix_sync( $user )->main::expect_http_401
            ->else_with_f( sub {
               my ( $f ) = @_; delay( $delay *= 1.5 )->then( sub { $f } );
            })
         };
      })->then( sub {
         my $delay = 0.1;
         # our access token should be invalidated
         try_repeat_until_success {
            matrix_sync( $other_login )->main::expect_http_401
            ->else_with_f( sub {
               my ( $f ) = @_; delay( $delay *= 1.5 )->then( sub { $f } );
            })
         };
      });
   };
