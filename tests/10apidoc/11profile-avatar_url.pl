my $avatar_url = "http://somewhere/my-pic.jpg";

test "PUT /profile/:user_id/avatar_url sets my avatar",
   requires => [qw( do_request_json_authed )],

   check => sub {
      my ( $do_request_json_authed ) = @_;

      $do_request_json_authed->(
         method => "GET",
         uri    => "/profile/:user_id/avatar_url",
      )->then( sub {
         my ( $body ) = @_;

         json_keys_ok( $body, qw( avatar_url ));

         $body->{avatar_url} eq $avatar_url or
            die "Expected avatar_url to be '$avatar_url'";

         provide can_set_avatar_url => 1;

         Future->done(1);
      });
   },

   do => sub {
      my ( $do_request_json_authed ) = @_;

      $do_request_json_authed->(
         method => "PUT",
         uri    => "/profile/:user_id/avatar_url",

         content => {
            avatar_url => $avatar_url,
         },
      );
   };

test "GET /events reports my avatar change",
   requires => [qw( GET_new_events user can_set_avatar_url )],

   check => sub {
      my ( $GET_new_events, $user ) = @_;

      $GET_new_events->( "m.presence" )->then( sub {
         my $found;

         foreach my $event ( @_ ) {
            my $content = $event->{content};
            json_keys_ok( $content, qw( user_id avatar_url ));

            next unless $content->{user_id} eq $user->user_id;
            $found++;

            $content->{avatar_url} eq $avatar_url or
               die "Expected avatar_url to be '$avatar_url'";
         }

         $found or
            die "Did not find expected presence event";

         Future->done(1);
      });
   };

test "GET /profile/:user_id/avatar_url publicly accessible",
   requires => [qw( first_http_client user can_set_avatar_url )],

   check => sub {
      my ( $http, $user ) = @_;
      my $user_id = $user->user_id;

      $http->do_request_json(
         method => "GET",
         uri    => "/profile/$user_id/avatar_url",
         # no access_token
      )->then( sub {
         my ( $body ) = @_;

         json_keys_ok( $body, qw( avatar_url ));

         $body->{avatar_url} eq $avatar_url or
            die "Expected avatar_url to be '$avatar_url'";

         Future->done(1);
      });
   };
