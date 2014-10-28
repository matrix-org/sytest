my $displayname = "Testing Displayname";

test "PUT /profile/:user_id/displayname sets my name",
   requires => [qw( do_request_json_authed )],

   check => sub {
      my ( $do_request_json_authed ) = @_;

      $do_request_json_authed->(
         method => "GET",
         uri    => "/profile/:user_id/displayname",
      )->then( sub {
         my ( $body ) = @_;

         json_keys_ok( $body, qw( displayname ));

         $body->{displayname} eq $displayname or die "Wrong displayname\n";

         provide can_set_displayname => 1;

         Future->done(1);
      });
   },

   do => sub {
      my ( $do_request_json_authed ) = @_;

      $do_request_json_authed->(
         method => "PUT",
         uri    => "/profile/:user_id/displayname",

         content => {
            displayname => $displayname,
         },
      );
   };

test "GET /events reports my name change",
   requires => [qw( GET_new_events user can_set_displayname )],

   check => sub {
      my ( $GET_new_events, $user ) = @_;

      $GET_new_events->( "m.presence" )->then( sub {
         my $found;

         foreach my $event ( @_ ) {
            my $content = $event->{content};
            json_keys_ok( $content, qw( user_id displayname ));

            next unless $content->{user_id} eq $user->user_id;
            $found++;

            $content->{displayname} eq $displayname or die "Expected displayname to be $displayname";
         }

         $found or
            die "Did not find expected presence event";

         Future->done(1);
      });
   };

test "GET /profile/:user_id/displayname publicly accessible",
   requires => [qw( first_http_client user can_set_displayname )],

   check => sub {
      my ( $http, $user ) = @_;
      my $user_id = $user->user_id;

      $http->do_request_json(
         method => "GET",
         uri    => "/profile/$user_id/displayname",
         # no access_token
      )->then( sub {
         my ( $body ) = @_;

         json_keys_ok( $body, qw( displayname ));

         $body->{displayname} eq $displayname or die "Wrong displayname\n";

         Future->done(1);
      });
   };
